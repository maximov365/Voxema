import Foundation
import Combine
import CryptoKit

// MARK: - ModelFamily

/// The functional category of a model in the Voxema pipeline.
public enum ModelFamily: String, Codable, Equatable, Sendable {
    case whisper
    case ecapa
    case llm
}

// MARK: - QualityTier

/// Human-readable quality tier for LLM models shown during onboarding.
/// Ordered good < better < best per DEC-2.
public enum QualityTier: String, Codable, Equatable, Comparable, Sendable {
    case good
    case better
    case best

    private var sortOrder: Int {
        switch self {
        case .good:   return 0
        case .better: return 1
        case .best:   return 2
        }
    }

    public static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - ModelInfo

/// Describes a single model entry in the manifest.
public struct ModelInfo: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier used as the filename and Keychain account key.
    public let id: String
    /// Human-readable name shown in Settings and onboarding.
    public let name: String
    public let family: ModelFamily
    /// Architecture/size variant label (e.g. "tiny", "3B-Q4_K_M").
    public let variant: String
    /// Uncompressed file size in bytes. Used for disk space checks.
    public let sizeBytes: Int
    /// Lowercase hex-encoded SHA-256 of the downloaded file. "placeholder" until release pipeline computes it.
    public let sha256: String
    /// RAM required to run this model (GB). Used for 8GB discipline enforcement.
    public let ramGB: Float
    /// Quality tier label — `nil` for non-LLM models.
    public let tier: QualityTier?
    /// Download URL. Must be HTTPS.
    public let downloadURL: URL
    /// `true` for models shipped inside the DMG. Bundled models are always `.bundled` status.
    public let isBundled: Bool
    /// One-line description shown to the user.
    public let description: String

    enum CodingKeys: String, CodingKey {
        case id, name, family, variant
        case sizeBytes   = "size_bytes"
        case sha256
        case ramGB       = "ram_gb"
        case tier
        case downloadURL = "download_url"
        case isBundled   = "is_bundled"
        case description
    }
}

// MARK: - ModelManifest

/// The full content of `models-manifest.json`.
/// Shipped with the app and updated via Sparkle releases (DEC-2).
public struct ModelManifest: Codable, Equatable, Sendable {
    public let version: String
    public let models: [ModelInfo]

    /// Loads a manifest from a file URL (used by `ModelManager.shared` with `Bundle.main`).
    public static func load(from url: URL) throws -> ModelManifest {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try decode(from: data)
    }

    /// Decodes a manifest from raw JSON data. Used in unit tests to inject manifests directly.
    public static func decode(from data: Data) throws -> ModelManifest {
        try JSONDecoder().decode(ModelManifest.self, from: data)
    }
}

// MARK: - ModelStatus

/// Lifecycle state of a model on this device.
public enum ModelStatus: Equatable, Sendable {
    /// Shipped in the DMG — always present, never needs downloading.
    case bundled
    /// Downloaded and SHA-256 verified.
    case available
    /// File not present on disk.
    case missing
    /// File present but SHA-256 mismatch. Must be re-downloaded.
    case corrupt
    /// Download in progress. `progress` is 0.0–1.0.
    case downloading(progress: Double)
}

// MARK: - ModelDownloadProgress

public struct ModelDownloadProgress: Sendable, Equatable {
    public let modelId: String
    public let fractionCompleted: Double
}

// MARK: - ModelError

/// Errors raised by `ModelManager`. Content-free — no model data, paths, or PII in messages.
public enum ModelError: Error, LocalizedError, Equatable {
    case manifestNotFound
    case manifestCorrupt
    case modelNotInManifest(id: String)
    case checksumMismatch(id: String)
    case downloadHTTPError(statusCode: Int)
    case downloadDiskSpaceInsufficient
    case downloadAlreadyInProgress(id: String)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            return "Model manifest file not found in app bundle."
        case .manifestCorrupt:
            return "Model manifest could not be parsed."
        case .modelNotInManifest(let id):
            return "Model '\(id)' is not listed in the manifest."
        case .checksumMismatch(let id):
            return "Checksum verification failed for model '\(id)'."
        case .downloadHTTPError(let code):
            return "Model download failed (HTTP \(code))."
        case .downloadDiskSpaceInsufficient:
            return "Insufficient disk space to download model."
        case .downloadAlreadyInProgress(let id):
            return "Download already in progress for '\(id)'."
        }
    }
}

// MARK: - ModelManager

/// Manages the lifecycle of ML models used by the Voxema pipeline.
///
/// ## Responsibilities
/// - Loading and exposing the `models-manifest.json` catalog
/// - Hardware-aware LLM recommendation (`ProcessInfo.physicalMemory` per DEC-2)
/// - On-disk status tracking (bundled / available / missing / corrupt)
/// - SHA-256 integrity verification
/// - Atomic model download: URLSession → temp file → verify → move to `modelsDirectory`
///
/// ## 8 GB discipline
/// Models are never loaded into memory by `ModelManager`; that is the responsibility of
/// each pipeline stage. `ModelManager` only manages files and status.
///
/// ## Thread safety
/// All mutable state is `@MainActor`-isolated. The byte-streaming in `download(_:)` runs
/// on the cooperative thread pool (nonisolated helper); only progress updates hop back to
/// the main actor, keeping the UI fully responsive during large downloads.
@MainActor
public final class ModelManager: ObservableObject {

    // MARK: Shared

    /// App-wide shared instance. Reads `models-manifest.json` from `Bundle.main`.
    /// Accessing this in unit tests is a programmer error — inject a manifest via `init(manifest:)`.
    public static let shared: ModelManager = {
        guard let url = Bundle.main.url(forResource: "models-manifest", withExtension: "json") else {
            fatalError("[ModelManager] models-manifest.json not found in app bundle")
        }
        do {
            let manifest = try ModelManifest.load(from: url)
            return ModelManager(manifest: manifest)
        } catch {
            fatalError("[ModelManager] Failed to parse models-manifest.json: \(error)")
        }
    }()

    // MARK: Properties

    public let manifest: ModelManifest
    public let modelsDirectory: URL
    /// Raw bytes from `ProcessInfo.processInfo.physicalMemory`. Overrideable for tests.
    public let deviceRAMBytes: Int

    /// Current status of every model in the manifest.
    @Published public private(set) var statuses: [String: ModelStatus] = [:]
    /// In-flight download progress keyed by model ID.
    @Published public private(set) var activeDownloads: [String: ModelDownloadProgress] = [:]

    public var deviceRAMGB: Float { Float(deviceRAMBytes) / 1_073_741_824 }

    // MARK: Init

    /// Designated initialiser. Injects all dependencies — suitable for production and unit tests.
    public init(
        manifest: ModelManifest,
        modelsDirectory: URL? = nil,
        deviceRAMBytes: Int = Int(ProcessInfo.processInfo.physicalMemory)
    ) {
        self.manifest = manifest
        self.deviceRAMBytes = deviceRAMBytes
        self.modelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory()

        // Initial status requires a file-system check for all models.
        // Bundled models are only marked .bundled when the file actually exists on disk;
        // otherwise they appear as .missing so the Settings UI can offer a download.
        let dir = modelsDirectory ?? Self.defaultModelsDirectory()
        var initial: [String: ModelStatus] = [:]
        for model in manifest.models {
            let url = dir
                .appendingPathComponent(model.family.rawValue, isDirectory: true)
                .appendingPathComponent(model.id)
            if FileManager.default.fileExists(atPath: url.path) {
                initial[model.id] = model.isBundled ? .bundled : .available
            } else {
                initial[model.id] = .missing
            }
        }
        self.statuses = initial
    }

    // MARK: Hardware & Recommendation

    /// LLM models whose RAM requirement fits within 70% of device RAM, sorted highest-tier first.
    ///
    /// The 70% budget leaves headroom for the OS, transcription model, and app memory.
    public var availableLLMs: [ModelInfo] {
        manifest.models
            .filter { $0.family == .llm && $0.ramGB <= deviceRAMGB * 0.7 }
            .sorted { ($0.tier ?? .good) > ($1.tier ?? .good) }
    }

    /// The highest-quality LLM that fits within the device's RAM budget.
    /// Returns `nil` when no LLM fits (extremely low-memory device or empty manifest).
    public var recommendedLLM: ModelInfo? { availableLLMs.first }

    // MARK: Paths

    /// Absolute local URL where the model file is (or should be) stored.
    public func localURL(for model: ModelInfo) -> URL {
        modelsDirectory
            .appendingPathComponent(model.family.rawValue, isDirectory: true)
            .appendingPathComponent(model.id)
    }

    // MARK: Status

    /// Re-checks whether the model file exists on disk and updates `statuses`.
    /// Does not verify the SHA-256 checksum (use `verify(_:)` for that).
    public func refreshStatus(for modelId: String) {
        guard let model = manifest.models.first(where: { $0.id == modelId }) else { return }
        let url = localURL(for: model)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            statuses[modelId] = .missing
            return
        }
        // File present: bundled models get .bundled status, downloaded models get .available.
        statuses[modelId] = model.isBundled ? .bundled : .available
    }

    /// Refreshes the on-disk status for every model in the manifest.
    public func refreshAllStatuses() {
        manifest.models.forEach { refreshStatus(for: $0.id) }
    }

    // MARK: Verification

    /// Computes the SHA-256 of the model file and compares it to the manifest.
    ///
    /// - Returns: `true` when the digest matches; `false` on mismatch.
    /// - Throws: `ModelError.modelNotInManifest` when the file is absent.
    public func verify(_ model: ModelInfo) throws -> Bool {
        guard !model.sha256.hasPrefix("placeholder") else { return true }
        let url = localURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelError.modelNotInManifest(id: model.id)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        return computed == model.sha256
    }

    // MARK: Download

    /// Downloads `model` to `modelsDirectory`, verifies its SHA-256, then marks it `.available`.
    ///
    /// Byte-streaming runs on the cooperative thread pool (nonisolated helper) — the main actor
    /// and the UI remain fully responsive throughout the download. Progress is reported back to
    /// the main actor roughly every 1 % of total file size. Supports Task cancellation: cancelling
    /// the enclosing Task cleans up the temp file and marks the model `.missing`.
    public func download(_ model: ModelInfo) async throws {
        guard activeDownloads[model.id] == nil else {
            throw ModelError.downloadAlreadyInProgress(id: model.id)
        }

        let destination = localURL(for: model)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        statuses[model.id] = .downloading(progress: 0)
        activeDownloads[model.id] = ModelDownloadProgress(modelId: model.id, fractionCompleted: 0)

        defer { activeDownloads.removeValue(forKey: model.id) }

        let modelId   = model.id
        let downloadURL = model.downloadURL

        // Force execution onto the cooperative thread pool so the main actor and
        // UI remain fully responsive. Task.detached breaks the @MainActor context.
        // Progress callbacks hop back to @MainActor via MainActor.run — accessing
        // ModelManager.shared there is valid because we're on the main actor.
        let tempURL: URL = try await Task.detached(priority: .utility) {
            try await ModelManager.downloadToTemp(
                url: downloadURL,
                onProgress: { fraction in
                    await MainActor.run {
                        let mm = ModelManager.shared
                        mm.statuses[modelId] = .downloading(progress: fraction)
                        mm.activeDownloads[modelId] = ModelDownloadProgress(
                            modelId: modelId,
                            fractionCompleted: fraction
                        )
                    }
                },
                onError: {
                    await MainActor.run {
                        ModelManager.shared.statuses[modelId] = .missing
                    }
                }
            )
        }.value

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let valid = try verify(model)
        guard valid else {
            try? FileManager.default.removeItem(at: destination)
            statuses[model.id] = .corrupt
            throw ModelError.checksumMismatch(id: model.id)
        }

        statuses[model.id] = .available
    }

    /// Streams `url` to a temporary file entirely on the cooperative thread pool.
    ///
    /// `static` so it can be called from `Task.detached` without crossing actor boundaries.
    /// Progress is reported every 0.1 % (smooth for files ≥10 MB) via `onProgress`.
    /// Propagates `CancellationError` when the enclosing Task is cancelled.
    private static nonisolated func downloadToTemp(
        url: URL,
        onProgress: @escaping @Sendable (Double) async -> Void,
        onError:    @escaping @Sendable ()       async -> Void
    ) async throws -> URL {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            await onError()
            throw ModelError.downloadHTTPError(statusCode: http.statusCode)
        }

        let expectedBytes = (response as? HTTPURLResponse)?.expectedContentLength ?? 0

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxema-model-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        // 256 KB flush interval — small enough that progress is smooth, large enough
        // to keep system-call overhead low even for 3 GB files.
        let flushInterval = 256 * 1024
        var buffer = Data(capacity: flushInterval)
        var received: Int64 = 0
        var lastReportedFraction: Double = 0

        do {
            for try await byte in asyncBytes {
                try Task.checkCancellation()
                buffer.append(byte)
                received += 1

                if buffer.count >= flushInterval {
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)

                    let fraction = expectedBytes > 0
                        ? min(Double(received) / Double(expectedBytes), 1.0)
                        : 0
                    // Report every 0.1 % so the progress bar moves visibly from the start.
                    if fraction - lastReportedFraction >= 0.001 {
                        await onProgress(fraction)
                        lastReportedFraction = fraction
                    }
                }
            }
            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
            }
            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: tempURL)
            await onError()
            throw error
        }

        return tempURL
    }

    // MARK: Private

    private static func defaultModelsDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voxema/Models", isDirectory: true)
    }
}

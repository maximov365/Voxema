import SwiftUI
import Combine
import AVFoundation

// MARK: - Data models

struct MicDevice: Identifiable, Equatable {
    let id: String        // AVCaptureDevice.uniqueID
    let name: String      // AVCaptureDevice.localizedName
    let isBuiltIn: Bool
}

struct WhisperModelTier: Identifiable {
    enum BadgeColor { case green, blue, purple }
    let id: String           // model key passed to ModelManager
    let tierName: String     // "Good", "Better", "Best"
    let modelLabel: String   // "whisper-small"
    let size: String         // "244 MB"
    let description: String
    let badgeLabel: String
    let badgeColor: BadgeColor
}

// MARK: - Step enum

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case configure
    case download
    case summarization
    case ready

    var isFirst: Bool { self == .welcome }
    var isLast:  Bool { self == .ready }
}

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {

    // Navigation
    @Published private(set) var step: OnboardingStep = .welcome

    // Permissions
    @Published private(set) var microphoneGranted = false

    // Configure step
    @Published var selectedMicID: String? = nil
    @Published var availableMics: [MicDevice] = []
    @Published var selectedWhisperModel: String? = nil
    @Published var availableWhisperTiers: [WhisperModelTier] = []
    @Published private(set) var detectedHardwareLabel: String = ""
    @Published private(set) var recommendedTierId: String = "whisper-medium"

    // Download step
    @Published private(set) var isDownloading   = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadError: String? = nil
    @Published var skipDownload = false
    private var cancellable: AnyCancellable?
    private var downloadTask: Task<Void, Never>?

    /// Human-readable "X MB / Y GB" progress label derived from fraction + manifest size.
    var downloadSizeLabel: String {
        guard let modelID = selectedWhisperModel,
              let model = ModelManager.shared.manifest.models.first(where: { $0.id == modelID }) else {
            return ""
        }
        let total = Double(model.sizeBytes)
        let totalStr = formatBytes(total)
        guard downloadProgress > 0 else { return totalStr }
        return "\(formatBytes(downloadProgress * total)) / \(totalStr)"
    }

    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", bytes / 1_000_000_000) }
        if bytes >= 1_000_000     { return String(format: "%.0f MB", bytes / 1_000_000) }
        return String(format: "%.0f KB", bytes / 1_000)
    }

    // Summarization step
    @Published var selectedSummarizationTier = 1   // 0=local-light, 1=local-mid, 2=cloud
    @Published var cloudAPIKey = ""

    // Completion callback
    var onComplete: (() -> Void)?

    init() {
        cloudAPIKey = CloudProvider.loadAPIKey() ?? ""
        refreshPermissions()
        loadMicrophoneList()
        loadWhisperModels()
    }

    // MARK: Navigation

    func advance() {
        guard !step.isLast else { complete(); return }
        let next = OnboardingStep(rawValue: step.rawValue + 1)!
        if next == .microphone && microphoneGranted { step = .configure; return }
        step = next
    }

    func goBack() {
        guard !step.isFirst else { return }
        step = OnboardingStep(rawValue: step.rawValue - 1)!
    }

    func complete() {
        // Persist cloud API key if cloud tier selected
        if selectedSummarizationTier == 2 && !cloudAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            try? CloudProvider.storeAPIKey(cloudAPIKey.trimmingCharacters(in: .whitespaces))
        }
        // Persist pipeline preferences so AppState.production() picks them up on next launch
        let prefs = AppPreferences.shared
        prefs.microphoneDeviceUID   = selectedMicID ?? ""
        prefs.whisperModelId        = selectedWhisperModel ?? ""
        prefs.summarizationProvider = selectedSummarizationTier == 2 ? "cloud" : "local"
        // Map summarization tier → LLM model ID from manifest
        if selectedSummarizationTier != 2 {
            let mm   = ModelManager.shared
            let llms = mm.availableLLMs
            let llm: ModelInfo? = selectedSummarizationTier == 0
                ? llms.last                  // lowest tier = smallest model
                : (llms.first { $0.tier == .better } ?? llms.first)
            prefs.llmModelId = llm?.id ?? ""
        }
        onComplete?()
    }

    // MARK: Permissions

    func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func startPermissionPolling() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in self?.microphoneGranted = granted }
        }
    }

    // MARK: Configure

    private func loadMicrophoneList() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = session.devices
        availableMics = devices.map {
            MicDevice(id: $0.uniqueID,
                      name: $0.localizedName,
                      isBuiltIn: $0.deviceType == .builtInMicrophone)
        }
        if selectedMicID == nil { selectedMicID = devices.first?.uniqueID }
    }

    private func loadWhisperModels() {
        availableWhisperTiers = [
            WhisperModelTier(
                id: "whisper-small",
                tierName: String(localized: "Good"),
                modelLabel: "whisper-small",
                size: "244 MB",
                description: String(localized: "Faster. Works great for clear audio and shorter meetings."),
                badgeLabel: String(localized: "Fastest"),
                badgeColor: .green
            ),
            WhisperModelTier(
                id: "whisper-medium",
                tierName: String(localized: "Better"),
                modelLabel: "whisper-medium",
                size: "769 MB",
                description: String(localized: "Balanced quality and speed. Best for most Mac setups."),
                badgeLabel: String(localized: "Recommended"),
                badgeColor: .blue
            ),
            WhisperModelTier(
                id: "whisper-large-v3",
                tierName: String(localized: "Best"),
                modelLabel: "whisper-large-v3",
                size: "1.5 GB",
                description: String(localized: "Highest accuracy. Best for multilingual or noisy environments."),
                badgeLabel: String(localized: "Best quality"),
                badgeColor: .purple
            ),
        ]
        detectHardware()
    }

    private func detectHardware() {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let name = macModelName()
        if ramGB >= 16 {
            recommendedTierId   = "whisper-medium"
            selectedWhisperModel = "whisper-medium"
            detectedHardwareLabel = "\(name) (\(ramGB) GB RAM) — Better tier recommended"
        } else {
            recommendedTierId   = "whisper-small"
            selectedWhisperModel = "whisper-small"
            detectedHardwareLabel = "\(name) (\(ramGB) GB RAM) — Good tier recommended"
        }
    }

    private func macModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        let hw = String(cString: chars)
        if hw.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if hw.hasPrefix("MacBookAir") { return "MacBook Air" }
        if hw.hasPrefix("MacPro")     { return "Mac Pro" }
        if hw.hasPrefix("Macmini")    { return "Mac mini" }
        if hw.hasPrefix("iMac")       { return "iMac" }
        return "Mac"
    }

    // MARK: Download

    func startModelDownload() {
        guard let modelID = selectedWhisperModel else { advance(); return }

        let mm = ModelManager.shared

        guard let model = mm.manifest.models.first(where: { $0.id == modelID }) else {
            advance()
            return
        }

        // Already on disk — skip straight through
        switch mm.statuses[modelID] {
        case .available, .bundled:
            advance()
            return
        default:
            break
        }

        isDownloading = true
        downloadError = nil
        downloadProgress = 0

        // Observe ModelManager progress on each status update
        cancellable = mm.$statuses
            .receive(on: RunLoop.main)
            .compactMap { $0[modelID] }
            .sink { [weak self] status in
                guard let self else { return }
                if case .downloading(let p) = status {
                    self.downloadProgress = p
                }
            }

        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await mm.download(model)
                self.cancellable = nil
                self.downloadTask = nil
                self.isDownloading = false
                self.advance()
            } catch is CancellationError {
                self.cancellable = nil
                self.downloadTask = nil
                self.isDownloading = false
            } catch {
                self.cancellable = nil
                self.downloadTask = nil
                self.isDownloading = false
                self.downloadError = error.localizedDescription
            }
        }
    }

    func skipModelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        cancellable = nil
        isDownloading = false
        skipDownload = true
        advance()
    }
}

// MARK: - Root OnboardingView

struct OnboardingView: View {

    @StateObject private var vm = OnboardingViewModel()
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 24)
                .padding(.bottom, 8)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
        .frame(width: 480, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            vm.onComplete = onComplete
            vm.refreshPermissions()
            vm.startPermissionPolling()
        }
    }

    // MARK: Progress dots (pill for active, green for past, gray for future)

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                if s == vm.step {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 8)
                } else if s.rawValue < vm.step.rawValue {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .animation(.spring(response: 0.3), value: vm.step)
    }

    // MARK: Step routing

    @ViewBuilder
    private var stepContent: some View {
        switch vm.step {
        case .welcome:       WelcomeStep(vm: vm)
        case .microphone:    MicrophoneStep(vm: vm)
        case .configure:     ConfigureStep(vm: vm)
        case .download:      DownloadStep(vm: vm)
        case .summarization: SummarizationStep(vm: vm)
        case .ready:         ReadyStep(vm: vm)
        }
    }

    // MARK: Navigation buttons

    @ViewBuilder
    private var navigationButtons: some View {
        switch vm.step {
        case .welcome:
            primaryButton(label: String(localized: "Get Started")) { vm.advance() }

        case .microphone:
            VStack(spacing: 10) {
                primaryButton(
                    label: vm.microphoneGranted
                        ? String(localized: "Continue →")
                        : String(localized: "Allow Microphone Access")
                ) {
                    if vm.microphoneGranted { vm.advance() }
                    else { vm.requestMicrophonePermission() }
                }
                if !vm.microphoneGranted { skipButton { vm.advance() } }
            }

        case .configure:
            HStack {
                backButton
                Spacer()
                primaryButton(label: String(localized: "Continue →")) { vm.advance() }
            }

        case .download:
            HStack(spacing: 10) {
                if !vm.isDownloading { backButton }
                Spacer()
                Button(String(localized: "Skip for now")) { vm.skipModelDownload() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                if !vm.isDownloading && vm.downloadError == nil {
                    primaryButton(label: String(localized: "Download")) { vm.startModelDownload() }
                }
            }

        case .summarization:
            HStack {
                backButton
                Spacer()
                primaryButton(label: String(localized: "Continue →")) { vm.advance() }
            }

        case .ready:
            primaryButton(label: String(localized: "Start Recording")) { vm.complete() }
        }
    }

    // MARK: Button helpers

    private func primaryButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.accentColor)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var backButton: some View {
        Button(String(localized: "← Back")) { vm.goBack() }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
    }

    private func skipButton(action: @escaping () -> Void) -> some View {
        Button(String(localized: "Skip for now →"), action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.secondary)
    }
}

// MARK: - Step views

// ── Welcome ───────────────────────────────────────────────────────────────────

private struct WelcomeStep: View {
    let vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            brandMark(size: 80)
            VStack(spacing: 8) {
                Text("Voxema")
                    .font(.system(size: 32, weight: .bold))
                Text(String(localized: "Your meetings. Your data. Your device."))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "mic.fill", color: .accentColor,
                           text: String(localized: "Captures your microphone and system audio — both sides of the conversation"))
                featureRow(icon: "text.bubble", color: .accentColor,
                           text: String(localized: "Transcribes, identifies speakers, and generates structured summaries"))
                featureRow(icon: "lock.fill", color: .green,
                           text: String(localized: "Everything stays on your Mac. Audio never leaves your device."))
            }
            .padding(.horizontal, 8)
            Spacer()
        }
    }
}

// ── Microphone ────────────────────────────────────────────────────────────────

private struct MicrophoneStep: View {
    @ObservedObject var vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            permissionIcon(systemName: "mic.fill", granted: vm.microphoneGranted)
            stepHeading(
                title: String(localized: "Microphone Access"),
                subtitle: String(localized: "Required to record your side of the conversation.\n\nVoxema uses a separate microphone channel so your voice is transcribed accurately.")
            )
            statusBadge(
                granted: vm.microphoneGranted,
                label: vm.microphoneGranted
                    ? String(localized: "Granted")
                    : String(localized: "Not granted")
            )
            Spacer()
        }
        .onAppear { vm.refreshPermissions() }
    }
}

// ── Configure ─────────────────────────────────────────────────────────────────

private struct ConfigureStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                // ── Microphone ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Choose your microphone"))
                        .font(.system(size: 15, weight: .semibold))
                    microphoneList
                }

                // ── Transcription quality ───────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Transcription quality"))
                            .font(.system(size: 15, weight: .semibold))
                        if !vm.detectedHardwareLabel.isEmpty {
                            Text("Detected: \(vm.detectedHardwareLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(vm.availableWhisperTiers) { tier in
                            tierCard(tier: tier)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Microphone list

    private var microphoneList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.availableMics.enumerated()), id: \.element.id) { idx, mic in
                micRow(mic: mic)
                if idx < vm.availableMics.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }

    private func micRow(mic: MicDevice) -> some View {
        let isSelected = vm.selectedMicID == mic.id
        return Button {
            vm.selectedMicID = mic.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: micIcon(for: mic))
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, alignment: .center)
                HStack(spacing: 5) {
                    Text(mic.name)
                        .font(.system(size: 13, weight: .medium))
                    if mic.isBuiltIn {
                        Text(String(localized: "(built-in)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Model tier cards

    private func tierCard(tier: WhisperModelTier) -> some View {
        let isSelected = vm.selectedWhisperModel == tier.id
        return Button {
            vm.selectedWhisperModel = tier.id
        } label: {
            HStack(spacing: 12) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                .animation(.spring(response: 0.2), value: isSelected)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(tier.tierName) — \(tier.modelLabel) · \(tier.size)")
                            .font(.system(size: 13, weight: .semibold))
                        badgeView(for: tier)
                        Spacer(minLength: 0)
                    }
                    Text(tier.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
    }

    @ViewBuilder
    private func badgeView(for tier: WhisperModelTier) -> some View {
        let (bg, fg) = badgeColors(tier.badgeColor)
        Text(tier.badgeLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private func badgeColors(_ color: WhisperModelTier.BadgeColor) -> (Color, Color) {
        switch color {
        case .green:  return (Color.green.opacity(0.15),        Color.green)
        case .blue:   return (Color.accentColor.opacity(0.15),  Color.accentColor)
        case .purple: return (Color.purple.opacity(0.15),       Color.purple)
        }
    }

    private func micIcon(for mic: MicDevice) -> String {
        let lower = mic.name.lowercased()
        if lower.contains("airpod") { return "airpodspro" }
        return "mic.fill"
    }
}

// ── Download ──────────────────────────────────────────────────────────────────

private struct DownloadStep: View {
    @ObservedObject var vm: OnboardingViewModel

    private var selectedTierName: String {
        vm.availableWhisperTiers.first { $0.id == vm.selectedWhisperModel }?.tierName
            ?? vm.selectedWhisperModel
            ?? String(localized: "model")
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            stepHeading(
                title: String(localized: "Download model"),
                subtitle: String(localized: "Downloading \(selectedTierName). The model is stored locally and used for all future transcriptions.")
            )
            if vm.isDownloading {
                VStack(spacing: 6) {
                    if vm.downloadProgress > 0 {
                        ProgressView(value: vm.downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        HStack {
                            Text("\(Int(vm.downloadProgress * 100))%")
                            Spacer()
                            Text(vm.downloadSizeLabel)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                        Text(String(localized: "Connecting…"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
            }
            if let err = vm.downloadError {
                VStack(spacing: 8) {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Retry")) { vm.startModelDownload() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Spacer()
        }
    }
}

// ── Summarization ─────────────────────────────────────────────────────────────

private struct SummarizationStep: View {
    @ObservedObject var vm: OnboardingViewModel
    private let tiers: [(title: String, subtitle: String, icon: String)] = [
        (String(localized: "Local — Lightweight"),
         String(localized: "Faster, uses less memory. Good for shorter meetings."), "cpu"),
        (String(localized: "Local — Recommended"),
         String(localized: "Best quality/performance balance for most Macs."), "cpu"),
        (String(localized: "Cloud"),
         String(localized: "Highest quality. Requires internet. API key needed."), "cloud"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            stepHeading(
                title: String(localized: "Summarization"),
                subtitle: String(localized: "Choose how Voxema generates meeting summaries. You can change this later.")
            )
            VStack(spacing: 8) {
                ForEach(tiers.indices, id: \.self) { i in tierRow(index: i) }
            }
            if vm.selectedSummarizationTier == 2 {
                SecureField(String(localized: "API key"), text: $vm.cloudAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
            Spacer()
        }
    }

    private func tierRow(index: Int) -> some View {
        let tier = tiers[index]
        let isSelected = vm.selectedSummarizationTier == index
        return Button { vm.selectedSummarizationTier = index } label: {
            HStack(spacing: 12) {
                Image(systemName: tier.icon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(tier.title).font(.system(size: 13, weight: .semibold))
                        if index == 1 {
                            Text(String(localized: "Recommended"))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    Text(tier.subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// ── Ready ─────────────────────────────────────────────────────────────────────

private struct ReadyStep: View {
    let vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            stepHeading(
                title: String(localized: "Ready"),
                subtitle: String(localized: "Voxema is configured and ready. Click Start Recording to capture your first meeting.")
            )
            VStack(alignment: .leading, spacing: 8) {
                readySummaryRow(
                    icon: vm.microphoneGranted ? "mic.fill" : "mic.slash.fill",
                    color: vm.microphoneGranted ? .green : .orange,
                    text: vm.microphoneGranted
                        ? String(localized: "Microphone — granted")
                        : String(localized: "Microphone — not granted")
                )
                readySummaryRow(
                    icon: "record.circle",
                    color: .secondary,
                    text: String(localized: "Screen Recording — checked on first recording")
                )
                readySummaryRow(
                    icon: "cpu",
                    color: .green,
                    text: vm.skipDownload
                        ? String(localized: "Transcription model — will download later")
                        : String(localized: "Transcription model — ready")
                )
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    private func readySummaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color).frame(width: 18)
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Shared UI helpers

private func brandMark(size: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: size * 0.2237)
            .fill(Color(red: 0.059, green: 0.082, blue: 0.098))
            .frame(width: size, height: size)
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let sc = w / 100
            let cx = 50 * sc, cy = 50 * sc
            var path: Path
            path = Path(ellipseIn: CGRect(x: cx - 14*sc, y: cy - 14*sc, width: 28*sc, height: 28*sc))
            ctx.stroke(path, with: .color(.white), lineWidth: 5*sc)
            func arc(_ r: CGFloat, color: Color, alpha: CGFloat) {
                var p = Path()
                p.addArc(center: CGPoint(x: cx, y: cy), radius: r*sc,
                         startAngle: .degrees(55), endAngle: .degrees(375), clockwise: false)
                ctx.stroke(p, with: .color(color.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 4.5*sc, lineCap: .round))
            }
            arc(23, color: .white,    alpha: 1.0)
            arc(32, color: Color(red: 0.5, green: 0.7, blue: 1.0), alpha: 1.0)
            arc(41, color: Color(red: 0.25, green: 0.5, blue: 0.75), alpha: 1.0)
        }
        .frame(width: size, height: size)
    }
}

private func stepHeading(title: String, subtitle: String) -> some View {
    VStack(spacing: 8) {
        Text(title).font(.system(size: 22, weight: .bold))
        Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func permissionIcon(systemName: String, granted: Bool) -> some View {
    ZStack {
        Circle()
            .fill(granted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
            .frame(width: 72, height: 72)
        Image(systemName: systemName)
            .font(.system(size: 30))
            .foregroundColor(granted ? .green : .accentColor)
    }
}

private func statusBadge(granted: Bool, label: String) -> some View {
    HStack(spacing: 6) {
        Circle()
            .fill(granted ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(granted ? .green : .orange)
    }
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background((granted ? Color.green : Color.orange).opacity(0.1))
    .cornerRadius(100)
}

private func featureRow(icon: String, color: Color, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon).foregroundColor(color).frame(width: 20)
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

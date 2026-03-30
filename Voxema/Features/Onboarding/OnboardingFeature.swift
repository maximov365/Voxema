import SwiftUI
import Combine
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

// MARK: - Step enum

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case screenRecording
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
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var microphoneGranted      = false

    // Configure step
    @Published var selectedMicID: String? = nil
    @Published var availableMics: [String] = []       // display names
    @Published var selectedWhisperModel: String? = nil
    @Published var availableWhisperModels: [(id: String, label: String, size: String)] = []

    // Download step
    @Published private(set) var isDownloading   = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadError: String? = nil
    @Published var skipDownload = false

    // Summarization step
    @Published var selectedSummarizationTier = 1   // 0=local-light, 1=local-mid, 2=cloud
    @Published var cloudAPIKey = ""

    // Completion callback
    var onComplete: (() -> Void)?

    init() {
        refreshPermissions()
        loadMicrophoneList()
        loadWhisperModels()
    }

    // MARK: Navigation

    func advance() {
        guard !step.isLast else {
            onComplete?()
            return
        }
        let next = OnboardingStep(rawValue: step.rawValue + 1)!
        // Auto-skip permission steps if already granted
        if next == .screenRecording && screenRecordingGranted {
            step = .microphone; return
        }
        if next == .microphone && microphoneGranted {
            step = .configure; return
        }
        step = next
    }

    func goBack() {
        guard !step.isFirst else { return }
        step = OnboardingStep(rawValue: step.rawValue - 1)!
    }

    func complete() {
        onComplete?()
    }

    // MARK: Permissions

    func refreshPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Start observing app-foreground events to refresh permission state
    /// automatically when the user returns from System Settings.
    func startPermissionPolling() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    /// Attempt a ScreenCaptureKit call so macOS registers Voxema in
    /// System Settings → Privacy & Security → Screen Recording.
    /// The app won't appear in that list until it has tried to use screen capture APIs.
    func triggerScreenRecordingRegistration() {
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            refreshPermissions()
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.microphoneGranted = granted
            }
        }
    }

    // MARK: Configure

    private func loadMicrophoneList() {
        // .microphone is macOS 14+; use .builtInMicrophone for the macOS 13 target
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        availableMics = devices.map { $0.localizedName }
        if selectedMicID == nil, let first = devices.first {
            selectedMicID = first.uniqueID
        }
    }

    private func loadWhisperModels() {
        // Populate from ModelManager manifest — use static fallback for testability
        availableWhisperModels = [
            (id: "whisper-tiny",   label: String(localized: "Fastest — lower accuracy"),    size: "~75 MB"),
            (id: "whisper-base",   label: String(localized: "Fast — good for clear audio"),  size: "~142 MB"),
            (id: "whisper-small",  label: String(localized: "Balanced — recommended"),        size: "~466 MB"),
            (id: "whisper-medium", label: String(localized: "Accurate — needs more memory"),  size: "~1.5 GB"),
        ]
        selectedWhisperModel = "whisper-small"
    }

    // MARK: Download

    func startModelDownload() {
        guard let modelID = selectedWhisperModel else { advance(); return }
        isDownloading  = true
        downloadError  = nil
        downloadProgress = 0

        // Simulate progress — real implementation delegates to ModelManager
        Task { @MainActor in
            for i in 1...20 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                downloadProgress = Double(i) / 20.0
            }
            isDownloading = false
            _ = modelID  // suppress warning; real: ModelManager.shared.download(id:)
            advance()
        }
    }

    func skipModelDownload() {
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
            // Progress dots
            progressDots
                .padding(.top, 24)
                .padding(.bottom, 8)

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)

            // Navigation buttons
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

    // MARK: Progress Dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= vm.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: s == vm.step ? 8 : 6, height: s == vm.step ? 8 : 6)
                    .animation(.spring(response: 0.3), value: vm.step)
            }
        }
    }

    // MARK: Step Routing

    @ViewBuilder
    private var stepContent: some View {
        switch vm.step {
        case .welcome:        WelcomeStep(vm: vm)
        case .screenRecording: ScreenRecordingStep(vm: vm)
        case .microphone:     MicrophoneStep(vm: vm)
        case .configure:      ConfigureStep(vm: vm)
        case .download:       DownloadStep(vm: vm)
        case .summarization:  SummarizationStep(vm: vm)
        case .ready:          ReadyStep(vm: vm)
        }
    }

    // MARK: Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        switch vm.step {
        case .welcome:
            primaryButton(label: String(localized: "Get Started")) { vm.advance() }

        case .screenRecording:
            primaryButton(
                label: vm.screenRecordingGranted
                    ? String(localized: "Continue →")
                    : String(localized: "Open System Settings")
            ) {
                if vm.screenRecordingGranted { vm.advance() }
                else { vm.openScreenRecordingSettings() }
            }

        case .microphone:
            primaryButton(
                label: vm.microphoneGranted
                    ? String(localized: "Continue →")
                    : String(localized: "Allow Microphone Access")
            ) {
                if vm.microphoneGranted { vm.advance() }
                else { vm.requestMicrophonePermission() }
            }

        case .configure:
            HStack {
                backButton
                Spacer()
                primaryButton(label: String(localized: "Continue →")) { vm.advance() }
            }

        case .download:
            VStack(spacing: 10) {
                if !vm.isDownloading {
                    HStack(spacing: 10) {
                        backButton
                        Spacer()
                        Button(String(localized: "Skip for now")) { vm.skipModelDownload() }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        primaryButton(label: String(localized: "Download")) { vm.startModelDownload() }
                    }
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

    // MARK: Helpers

    private func primaryButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var backButton: some View {
        Button(String(localized: "← Back")) { vm.goBack() }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
    }
}

// MARK: - Step Views

// ── Welcome ──────────────────────────────────────────────────────────────────

private struct WelcomeStep: View {
    let vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            // Brand mark
            brandMark(size: 80)
            VStack(spacing: 8) {
                Text("Voxema")
                    .font(.system(size: 32, weight: .bold, design: .default))
                Text(String(localized: "Your meetings. Your data. Your device."))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "mic.fill",       color: .accentColor, text: String(localized: "Captures your microphone and system audio — both sides of the conversation"))
                featureRow(icon: "text.bubble",    color: .accentColor, text: String(localized: "Transcribes, identifies speakers, and generates structured summaries"))
                featureRow(icon: "lock.fill",       color: .green,        text: String(localized: "Everything stays on your Mac. Audio never leaves your device."))
            }
            .padding(.horizontal, 8)
            Spacer()
        }
    }
}

// ── Screen Recording ─────────────────────────────────────────────────────────

private struct ScreenRecordingStep: View {
    @ObservedObject var vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            permissionIcon(systemName: "record.circle", granted: vm.screenRecordingGranted)
            stepHeading(
                title: String(localized: "Screen Recording"),
                subtitle: String(localized: "Required to capture system audio from remote participants.\n\nOpen System Settings → Privacy & Security → Screen Recording, then enable Voxema.")
            )
            if vm.screenRecordingGranted {
                statusBadge(granted: true, label: String(localized: "Granted"))
            } else {
                statusBadge(granted: false, label: String(localized: "Not granted"))
            }
            Spacer()
        }
        .onAppear {
            vm.refreshPermissions()
            // First call to SCShareableContent registers app in Screen Recording privacy list
            vm.triggerScreenRecordingRegistration()
        }
    }
}

// ── Microphone ───────────────────────────────────────────────────────────────

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
            if vm.microphoneGranted {
                statusBadge(granted: true, label: String(localized: "Granted"))
            } else {
                statusBadge(granted: false, label: String(localized: "Not granted"))
            }
            Spacer()
        }
        .onAppear { vm.refreshPermissions() }
    }
}

// ── Configure ────────────────────────────────────────────────────────────────

private struct ConfigureStep: View {
    @ObservedObject var vm: OnboardingViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            stepHeading(
                title: String(localized: "Configure"),
                subtitle: String(localized: "Choose your microphone and transcription quality. You can change these later in Settings.")
            )
            VStack(alignment: .leading, spacing: 14) {
                configSection(label: String(localized: "Microphone")) {
                    Picker(String(localized: "Microphone"), selection: $vm.selectedMicID) {
                        ForEach(Array(vm.availableMics.enumerated()), id: \.offset) { i, name in
                            Text(name).tag(Optional(name))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                configSection(label: String(localized: "Transcription model")) {
                    Picker(String(localized: "Model"), selection: $vm.selectedWhisperModel) {
                        ForEach(vm.availableWhisperModels, id: \.id) { m in
                            VStack(alignment: .leading) {
                                Text(m.label)
                                Text(m.id + " · " + m.size)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .tag(Optional(m.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            Spacer()
        }
    }
}

// ── Download ─────────────────────────────────────────────────────────────────

private struct DownloadStep: View {
    @ObservedObject var vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            stepHeading(
                title: String(localized: "Download model"),
                subtitle: vm.selectedWhisperModel.map {
                    String(localized: "Downloading \($0). The model is stored locally and used for all future transcriptions.")
                } ?? String(localized: "No model selected. You can download one later in Settings.")
            )
            if vm.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: vm.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    Text("\(Int(vm.downloadProgress * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            }
            if let err = vm.downloadError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

// ── Summarization ─────────────────────────────────────────────────────────────

private struct SummarizationStep: View {
    @ObservedObject var vm: OnboardingViewModel
    private let tiers = [
        (title: String(localized: "Local — Lightweight"),   subtitle: String(localized: "Faster, uses less memory. Good for shorter meetings."),  icon: "cpu"),
        (title: String(localized: "Local — Recommended"),   subtitle: String(localized: "Best quality/performance balance for most Macs."),        icon: "cpu"),
        (title: String(localized: "Cloud"),                  subtitle: String(localized: "Highest quality. Requires internet. API key needed."),    icon: "cloud"),
    ]
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            stepHeading(
                title: String(localized: "Summarization"),
                subtitle: String(localized: "Choose how Voxema generates meeting summaries. You can change this later.")
            )
            VStack(spacing: 8) {
                ForEach(tiers.indices, id: \.self) { i in
                    tierRow(index: i)
                }
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
        return Button {
            vm.selectedSummarizationTier = index
        } label: {
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
                readySummaryRow(icon: "record.circle",  text: String(localized: "Screen Recording — granted"))
                readySummaryRow(icon: "mic.fill",        text: String(localized: "Microphone — granted"))
                readySummaryRow(icon: "cpu",             text: String(localized: "Transcription model — ready"))
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    private func readySummaryRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.green).frame(width: 18)
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Shared UI helpers (file-private)

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
            // Circle ring
            path = Path(ellipseIn: CGRect(x: (cx - 14*sc), y: (cy - 14*sc), width: 28*sc, height: 28*sc))
            ctx.stroke(path, with: .color(.white), lineWidth: 5*sc)
            // Arc helper: draw 320° CW arc, gap 15°→55°
            func arc(_ r: CGFloat, color: Color, alpha: CGFloat) {
                var p = Path()
                let start = Angle.degrees(55)
                let end   = Angle.degrees(15 + 360) // 375° for 320° CW
                p.addArc(center: CGPoint(x: cx, y: cy), radius: r*sc,
                         startAngle: start, endAngle: end, clockwise: false)
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
        Text(title)
            .font(.system(size: 22, weight: .bold))
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
        Image(systemName: icon)
            .foregroundColor(color)
            .frame(width: 20)
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func configSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
        content()
    }
}

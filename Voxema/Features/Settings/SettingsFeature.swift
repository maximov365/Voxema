import SwiftUI
import AVFoundation

// MARK: - SettingsView

struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            ModelsSettingsTab()
                .tabItem { Label(String(localized: "Models"), systemImage: "cpu") }
            SummarizationSettingsTab()
                .tabItem { Label(String(localized: "Summarization"), systemImage: "text.bubble") }
            StorageSettingsTab()
                .tabItem { Label(String(localized: "Storage"), systemImage: "internaldrive") }
        }
        .frame(width: 500)
        .fixedSize()
    }
}

// MARK: - General Tab (Microphone)

private struct GeneralSettingsTab: View {

    @EnvironmentObject private var appState: AppState
    @State private var availableMics: [AVCaptureDevice] = []
    @State private var selectedUID: String = AppPreferences.shared.microphoneDeviceUID
    @State private var selectedLanguage: String = AppPreferences.shared.whisperLanguage

    private let languages: [(code: String, label: String)] = [
        ("auto",  "Auto-detect"),
        ("ru",    "Russian (ru)"),
        ("en",    "English (en)"),
        ("de",    "German (de)"),
        ("fr",    "French (fr)"),
        ("es",    "Spanish (es)"),
        ("it",    "Italian (it)"),
        ("zh",    "Chinese (zh)"),
        ("ja",    "Japanese (ja)"),
        ("ko",    "Korean (ko)"),
        ("pt",    "Portuguese (pt)"),
        ("nl",    "Dutch (nl)"),
        ("pl",    "Polish (pl)"),
        ("tr",    "Turkish (tr)"),
        ("uk",    "Ukrainian (uk)"),
    ]

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Input device"), selection: $selectedUID) {
                    Text(String(localized: "System Default")).tag("")
                    ForEach(availableMics, id: \.uniqueID) { mic in
                        Text(mic.localizedName).tag(mic.uniqueID)
                    }
                }
                .onChange(of: selectedUID) { AppPreferences.shared.microphoneDeviceUID = $0 }
            } header: {
                Text(String(localized: "Microphone"))
            } footer: {
                Text(String(localized: "Changes take effect on the next recording."))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "Transcription language"), selection: $selectedLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .onChange(of: selectedLanguage) {
                    AppPreferences.shared.whisperLanguage = $0
                    appState.refreshPipeline()
                }
            } header: {
                Text(String(localized: "Language"))
            } footer: {
                Text(String(localized: "Force a specific language to improve accuracy. Auto-detect works well for English; for other languages, setting explicitly gives significantly better results."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 260)
        .onAppear { loadMics() }
    }

    private func loadMics() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableMics = session.devices
    }
}

// MARK: - Models Tab (Whisper)

private struct ModelsSettingsTab: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var mm = ModelManager.shared
    @State private var selectedWhisperID: String = AppPreferences.shared.whisperModelId
    @State private var downloadError: String?

    private var whisperModels: [ModelInfo] {
        mm.manifest.models.filter { $0.family == .whisper }
    }

    var body: some View {
        Form {
            Section {
                ForEach(whisperModels) { model in
                    whisperRow(model)
                }
            } header: {
                Text(String(localized: "Transcription Model"))
            } footer: {
                if let err = downloadError {
                    Text(err).foregroundStyle(.red).font(.system(size: 11))
                } else {
                    Text(String(localized: "Select and download a model. Changes apply immediately after download."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 280)
        .onAppear { mm.refreshAllStatuses() }
    }

    @ViewBuilder
    private func whisperRow(_ model: ModelInfo) -> some View {
        let status = mm.statuses[model.id] ?? .missing
        let isSelected = selectedWhisperID == model.id
        let isReady = status == .bundled || status == .available

        HStack(spacing: 12) {
            // Radio button
            Button {
                guard isReady else { return }
                selectedWhisperID = model.id
                AppPreferences.shared.whisperModelId = model.id
                appState.refreshPipeline()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
            .opacity(isDownloading(status) || isReady ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                    statusBadge(status, model: model)
                }
                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .opacity(isDownloading(status) || isReady ? 1 : 0.5)

            Spacer()

            Text(bytesLabel(model.sizeBytes))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // Download button for non-bundled missing models
            if status == .missing || status == .corrupt {
                Button(String(localized: "Download")) {
                    downloadError = nil
                    Task {
                        do {
                            try await mm.download(model)
                            if mm.statuses[model.id] == .available {
                                selectedWhisperID = model.id
                                AppPreferences.shared.whisperModelId = model.id
                                appState.refreshPipeline()
                            }
                        } catch {
                            downloadError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Progress indicator
            if case .downloading(let p) = status {
                ProgressView(value: p)
                    .frame(width: 60)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
    }

    private func isDownloading(_ status: ModelStatus) -> Bool {
        if case .downloading = status { return true }
        return false
    }

    @ViewBuilder
    private func statusBadge(_ status: ModelStatus, model: ModelInfo) -> some View {
        switch status {
        case .bundled:
            badge(String(localized: "Bundled"), color: .green)
        case .available:
            badge(String(localized: "Ready"), color: .accentColor)
        case .corrupt:
            badge(String(localized: "Corrupt"), color: .orange)
        default:
            EmptyView()
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func bytesLabel(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1000 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - Summarization Tab

private struct SummarizationSettingsTab: View {

    @ObservedObject private var mm = ModelManager.shared
    @State private var selectedProvider: String = AppPreferences.shared.summarizationProvider
    @State private var selectedLLMID: String    = AppPreferences.shared.llmModelId
    @State private var apiKey: String           = CloudProvider.loadAPIKey() ?? ""
    @State private var showKey = false
    @State private var downloadError: String?

    private var llmModels: [ModelInfo] {
        mm.manifest.models.filter { $0.family == .llm }
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Provider"), selection: $selectedProvider) {
                    Text(String(localized: "Local model (offline, private)")).tag("local")
                    Text(String(localized: "Cloud API (OpenAI / Anthropic)")).tag("cloud")
                }
                .onChange(of: selectedProvider) { AppPreferences.shared.summarizationProvider = $0 }
            } header: {
                Text(String(localized: "Summarization"))
            }

            if selectedProvider == "local" {
                Section {
                    ForEach(llmModels) { model in
                        llmRow(model)
                    }
                    if llmModels.isEmpty {
                        Text(String(localized: "No LLM models in manifest."))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                } header: {
                    Text(String(localized: "Local LLM"))
                } footer: {
                    if let err = downloadError {
                        Text(err).foregroundStyle(.red).font(.system(size: 11))
                    }
                }
            }

            if selectedProvider == "cloud" {
                Section {
                    HStack {
                        if showKey {
                            TextField(String(localized: "sk-ant-… or sk-…"), text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField(String(localized: "API key"), text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button(String(localized: "Save")) {
                            let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            try? CloudProvider.storeAPIKey(trimmed)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(String(localized: "API Key"))
                } footer: {
                    Text(String(localized: "Your key is stored in the system Keychain. Audio never leaves your device — only the text transcript is sent to the cloud LLM, with your explicit consent before each session."))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text(String(localized: "Changes take effect on the next app launch."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 380)
        .onAppear { mm.refreshAllStatuses() }
    }

    @ViewBuilder
    private func llmRow(_ model: ModelInfo) -> some View {
        let status = mm.statuses[model.id] ?? .missing
        let isReady = status == .bundled || status == .available
        let isSelected = selectedLLMID == model.id

        HStack(spacing: 12) {
            Button {
                guard isReady else { return }
                selectedLLMID = model.id
                AppPreferences.shared.llmModelId = model.id
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
            .opacity(!isReady ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                    if let tier = model.tier {
                        tierBadge(tier)
                    }
                }
                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .opacity(!isReady ? 0.5 : 1)

            Spacer()

            if status == .missing || status == .corrupt {
                Button(String(localized: "Download")) {
                    downloadError = nil
                    Task {
                        do { try await mm.download(model) }
                        catch { downloadError = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if case .downloading(let p) = status {
                ProgressView(value: p).frame(width: 60).progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
    }

    private func tierBadge(_ tier: QualityTier) -> some View {
        let (label, color): (String, Color) = switch tier {
        case .good:   (String(localized: "Good"),   .green)
        case .better: (String(localized: "Better"), Color.accentColor)
        case .best:   (String(localized: "Best"),   .purple)
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Storage Settings Tab

private struct StorageSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var retentionDays: Int = AppPreferences.shared.audioRetentionDays
    @State private var showDeleteAllConfirmation = false

    private let retentionOptions: [(label: String, days: Int)] = [
        ("Delete after processing", 0),
        ("30 days",  30),
        ("3 months", 90),
        ("6 months", 180),
        ("Keep forever", -1),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Keep audio for", selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                .onChange(of: retentionDays) { newValue in
                    AppPreferences.shared.audioRetentionDays = newValue
                    if newValue >= 0 {
                        appState.cleanupExpiredAudio()
                    }
                }

                Text(retentionExplanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            } header: {
                Text("Audio Retention")
            }

            Section {
                HStack {
                    Text("Audio storage used")
                    Spacer()
                    Text(formattedStorageUsed)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All Audio Now", systemImage: "trash")
                }
                .disabled(appState.audioStorageUsedBytes == 0)
                .confirmationDialog(
                    "Delete All Audio Recordings?",
                    isPresented: $showDeleteAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete All Audio", role: .destructive) {
                        appState.deleteAllAudio()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Transcripts and summaries will be kept. This cannot be undone.")
                }
            } header: {
                Text("Usage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var formattedStorageUsed: String {
        let bytes = appState.audioStorageUsedBytes
        if bytes == 0 { return "0 KB" }
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }

    private var retentionExplanation: String {
        switch retentionDays {
        case 0:  return "Audio is deleted immediately after processing completes. Reprocessing will not be available."
        case -1: return "Audio is kept indefinitely until you delete it manually."
        default: return "Audio older than \(retentionLabel(retentionDays)) is deleted automatically on app launch."
        }
    }

    private func retentionLabel(_ days: Int) -> String {
        retentionOptions.first { $0.days == days }?.label.lowercased() ?? "\(days) days"
    }
}

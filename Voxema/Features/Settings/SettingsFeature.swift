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
                Text(String(localized: "Select and download a model. Changes apply immediately after download."))
                    .foregroundStyle(.secondary)
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

            Spacer()

            Text(bytesLabel(model.sizeBytes))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // Download button for non-bundled missing models
            if status == .missing || status == .corrupt {
                Button(String(localized: "Download")) {
                    Task {
                        try? await mm.download(model)
                        // Auto-select and activate this model once downloaded
                        if mm.statuses[model.id] == .available {
                            selectedWhisperID = model.id
                            AppPreferences.shared.whisperModelId = model.id
                            appState.refreshPipeline()
                        }
                    }
                }
                .buttonStyle(.bordered)
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
        .opacity(isDownloading(status) || isReady ? 1 : 0.5)
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
                Section(String(localized: "Local LLM")) {
                    ForEach(llmModels) { model in
                        llmRow(model)
                    }
                    if llmModels.isEmpty {
                        Text(String(localized: "No LLM models in manifest."))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
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

            Spacer()

            if status == .missing || status == .corrupt {
                Button(String(localized: "Download")) {
                    Task { try? await mm.download(model) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if case .downloading(let p) = status {
                ProgressView(value: p).frame(width: 60).progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
        .opacity(!isReady ? 0.5 : 1)
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

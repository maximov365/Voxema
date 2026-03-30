import Foundation

/// Central store for user-configurable app preferences.
///
/// Persisted via `UserDefaults`. Read by `AppState.production()` when building
/// pipeline stage configurations. Settings changes take effect on the next app launch
/// (model loading and device selection happen at startup, not mid-session).
public final class AppPreferences {

    public static let shared = AppPreferences()

    // MARK: - Keys

    private enum Keys {
        static let microphoneDeviceUID    = "voxema.microphoneDeviceUID"
        static let whisperModelId         = "voxema.whisperModelId"
        static let llmModelId             = "voxema.llmModelId"
        static let summarizationProvider  = "voxema.summarizationProvider"
    }

    // MARK: - Preferences

    /// AVCaptureDevice uniqueID of the selected microphone.
    /// Empty string means "use system default".
    public var microphoneDeviceUID: String {
        get { UserDefaults.standard.string(forKey: Keys.microphoneDeviceUID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.microphoneDeviceUID) }
    }

    /// Manifest model ID of the selected Whisper transcription model.
    /// Defaults to `"whisper-tiny"` (always bundled).
    public var whisperModelId: String {
        get { UserDefaults.standard.string(forKey: Keys.whisperModelId) ?? "whisper-tiny" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.whisperModelId) }
    }

    /// Manifest model ID of the selected local LLM for summarization.
    /// Empty string means "no local LLM downloaded / skip summarization".
    public var llmModelId: String {
        get { UserDefaults.standard.string(forKey: Keys.llmModelId) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.llmModelId) }
    }

    /// Raw `ProviderType` value: `"local"` or `"cloud"`.
    /// Defaults to `"local"`.
    public var summarizationProvider: String {
        get { UserDefaults.standard.string(forKey: Keys.summarizationProvider) ?? "local" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.summarizationProvider) }
    }

    private init() {}
}

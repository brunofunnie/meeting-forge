import Foundation
import Observation
import MeetingForgeCore

@Observable @MainActor
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.funnietech.meetingforge")

    var engineID: TranscriptionEngineID {
        didSet { defaults.set(engineID.rawValue, forKey: "engine") }
    }
    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: "whisper-model") }
    }
    var defaultProvider: ProviderID {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "default-provider") }
    }
    var claudeExecutablePath: String? {
        didSet { defaults.set(claudeExecutablePath, forKey: "claude-path") }
    }
    var priceOverrides: [String: ModelPrice] {
        didSet { defaults.set(try? JSONEncoder().encode(priceOverrides), forKey: "price-overrides") }
    }

    init() {
        engineID = TranscriptionEngineID(rawValue: defaults.string(forKey: "engine") ?? "") ?? .appleSpeech
        whisperModel = defaults.string(forKey: "whisper-model") ?? "openai_whisper-base"
        defaultProvider = ProviderID(rawValue: defaults.string(forKey: "default-provider") ?? "") ?? .anthropic
        claudeExecutablePath = defaults.string(forKey: "claude-path")
        if let data = defaults.data(forKey: "price-overrides"),
           let decoded = try? JSONDecoder().decode([String: ModelPrice].self, from: data) {
            priceOverrides = decoded
        } else {
            priceOverrides = [:]
        }
    }

    /// Per-provider default model, persisted individually under "default-model-<id>"
    /// rather than as a single blob, so a new provider added later needs no migration.
    func defaultModel(for provider: ProviderID) -> String? {
        defaults.string(forKey: "default-model-\(provider.rawValue)")
    }

    func setDefaultModel(_ model: String, for provider: ProviderID) {
        defaults.set(model, forKey: "default-model-\(provider.rawValue)")
    }

    func apiKey(for provider: ProviderID) -> String? {
        keychain.get(account: provider.rawValue)
    }

    func setAPIKey(_ key: String?, for provider: ProviderID) {
        if let key, !key.isEmpty {
            try? keychain.set(key, account: provider.rawValue)
        } else {
            try? keychain.delete(account: provider.rawValue)
        }
    }

    func claudeExecutableURL() -> URL? {
        if let path = claudeExecutablePath, !path.isEmpty {
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        return ClaudeCodeProvider.detectExecutable()
    }

    /// Provider is usable now: has an API key, or (Claude Code) the CLI is present.
    func isAvailable(_ id: ProviderID) -> Bool {
        if id == .claudeCode { return claudeExecutableURL() != nil }
        return !(apiKey(for: id) ?? "").isEmpty
    }

    func makeProvider(_ id: ProviderID) -> MinutesProvider {
        switch id {
        case .openAI: OpenAIProvider()
        case .anthropic: AnthropicProvider()
        case .gemini: GeminiProvider()
        case .ollamaCloud: OllamaCloudProvider()
        case .claudeCode: ClaudeCodeProvider(executableURL: claudeExecutableURL())
        }
    }

    func makeEngine() -> TranscriptionEngine {
        switch engineID {
        case .appleSpeech: AppleSpeechEngine()
        case .whisperKit: WhisperKitEngine(
            modelName: whisperModel, modelsDirectory: AppPaths.whisperModelsDirectory)
        }
    }

    func costCalculator() -> CostCalculator {
        CostCalculator(overrides: priceOverrides)
    }
}

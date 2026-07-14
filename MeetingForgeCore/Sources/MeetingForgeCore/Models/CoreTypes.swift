import Foundation

public enum MeetingForgeCoreInfo {
    public static let version = "0.1.0"
}

public enum MeetingLanguage: String, Codable, CaseIterable, Sendable {
    case portugueseBR = "pt-BR"
    case english = "en"
    case auto = "auto"

    /// Locale for speech APIs; nil means detect automatically.
    public var localeIdentifier: String? {
        switch self {
        case .portugueseBR: "pt_BR"
        case .english: "en_US"
        case .auto: nil
        }
    }

    public var displayName: String {
        switch self {
        case .portugueseBR: "Português (BR)"
        case .english: "English"
        case .auto: "Auto-detect"
        }
    }
}

/// Language the AI writes the minutes in — independent of the transcription language.
public enum MinutesLanguage: String, Codable, CaseIterable, Sendable {
    case matchTranscript = "match"
    case portugueseBR = "pt-BR"
    case english = "en"

    public var displayName: String {
        switch self {
        case .matchTranscript: "Same as audio"
        case .portugueseBR: "Português (BR)"
        case .english: "English"
        }
    }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: String?

    public init(start: TimeInterval, end: TimeInterval, text: String, speaker: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct SpeakerTurn: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speakerID: String

    public init(start: TimeInterval, end: TimeInterval, speakerID: String) {
        self.start = start
        self.end = end
        self.speakerID = speakerID
    }
}

public struct UsageStats: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Set only when the provider reports cost itself (Claude Code CLI).
    public var reportedCostUSD: Double?

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int, reportedCostUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reportedCostUSD = reportedCostUSD
    }
}

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case ollamaCloud = "ollama-cloud"
    case ollamaLocal = "ollama-local"
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic (Claude API)"
        case .gemini: "Google AI Studio (Gemini)"
        case .ollamaCloud: "Ollama Cloud"
        case .ollamaLocal: "Ollama (local)"
        case .claudeCode: "Claude Code"
        }
    }

    /// Providers that need an API key stored in Keychain.
    public var requiresAPIKey: Bool { self != .claudeCode && self != .ollamaLocal }
}

public enum TranscriptionEngineID: String, Codable, CaseIterable, Sendable {
    case appleSpeech = "apple-speech"
    case whisperKit = "whisperkit"

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech (built-in)"
        case .whisperKit: "WhisperKit (Whisper models)"
        }
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case pending, transcribing, generating, done, failed
}

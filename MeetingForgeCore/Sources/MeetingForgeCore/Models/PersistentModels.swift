import Foundation
import SwiftData

@Model
public final class Meeting {
    public var title: String
    public var createdAt: Date
    public var sourceFileNames: [String]
    public var combinedAudioPath: String?
    public var durationSeconds: Double
    public var languageRaw: String
    public var statusRaw: String
    /// UUID of this meeting's folder under Application Support/MeetingForge/audio.
    /// Optional so existing stores migrate lightweight (nil for pre-existing meetings).
    public var audioFolderUUID: String?
    /// Minutes output language chosen at run time; optional for lightweight migration.
    public var minutesLanguageRaw: String?

    @Relationship(deleteRule: .cascade) public var transcript: Transcript?
    @Relationship(deleteRule: .cascade) public var minutesRuns: [MinutesRun]

    public var language: MeetingLanguage {
        get { MeetingLanguage(rawValue: languageRaw) ?? .auto }
        set { languageRaw = newValue.rawValue }
    }

    public var minutesLanguage: MinutesLanguage {
        get { minutesLanguageRaw.flatMap(MinutesLanguage.init(rawValue:)) ?? .matchTranscript }
        set { minutesLanguageRaw = newValue.rawValue }
    }

    public var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(title: String, language: MeetingLanguage, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
        self.sourceFileNames = []
        self.combinedAudioPath = nil
        self.durationSeconds = 0
        self.languageRaw = language.rawValue
        self.statusRaw = MeetingStatus.pending.rawValue
        self.audioFolderUUID = nil
        self.minutesRuns = []
    }
}

@Model
public final class Transcript {
    public var text: String
    public var segmentsData: Data
    public var engineRaw: String
    public var diarized: Bool
    public var wallTimeSeconds: Double
    public var speakerNamesData: Data

    public var engine: TranscriptionEngineID {
        get { TranscriptionEngineID(rawValue: engineRaw) ?? .appleSpeech }
        set { engineRaw = newValue.rawValue }
    }

    public init(engine: TranscriptionEngineID, diarized: Bool) {
        self.text = ""
        self.segmentsData = Data("[]".utf8)
        self.engineRaw = engine.rawValue
        self.diarized = diarized
        self.wallTimeSeconds = 0
        self.speakerNamesData = Data("{}".utf8)
    }

    public func segments() throws -> [TranscriptSegment] {
        try JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)
    }

    public func setSegments(_ segments: [TranscriptSegment]) throws {
        segmentsData = try JSONEncoder().encode(segments)
        text = segments.map(\.text).joined(separator: " ")
    }

    public func speakerNames() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: speakerNamesData)
    }

    public func setSpeakerNames(_ names: [String: String]) throws {
        speakerNamesData = try JSONEncoder().encode(names)
    }
}

@Model
public final class MinutesRun {
    public var createdAt: Date
    public var markdown: String
    public var providerRaw: String
    public var modelName: String
    public var templateName: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double
    public var latencySeconds: Double

    public var provider: ProviderID {
        get { ProviderID(rawValue: providerRaw) ?? .openAI }
        set { providerRaw = newValue.rawValue }
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(provider: ProviderID, modelName: String, templateName: String,
                markdown: String, inputTokens: Int, outputTokens: Int,
                costUSD: Double, latencySeconds: Double, createdAt: Date = .now) {
        self.createdAt = createdAt
        self.markdown = markdown
        self.providerRaw = provider.rawValue
        self.modelName = modelName
        self.templateName = templateName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.latencySeconds = latencySeconds
    }
}

@Model
public final class MeetingTemplate {
    public var name: String
    public var icon: String
    public var systemPrompt: String
    public var sections: [String]
    public var isBuiltin: Bool
    /// Stable key for builtins so "reset to default" can find the original.
    public var builtinKey: String?

    public init(name: String, icon: String, systemPrompt: String,
                sections: [String], isBuiltin: Bool = false, builtinKey: String? = nil) {
        self.name = name
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.sections = sections
        self.isBuiltin = isBuiltin
        self.builtinKey = builtinKey
    }
}

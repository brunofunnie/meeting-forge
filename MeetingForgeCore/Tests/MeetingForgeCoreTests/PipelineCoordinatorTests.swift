import Testing
import Foundation
@testable import MeetingForgeCore

struct FakeEngine: TranscriptionEngine {
    let id: TranscriptionEngineID = .appleSpeech
    var segments: [TranscriptSegment] = [TranscriptSegment(start: 0, end: 2, text: "hello world")]
    var error: TranscriptionError?
    func prepare(language: MeetingLanguage) async throws {}
    func transcribe(fileURL: URL, language: MeetingLanguage,
                    onProgress: @escaping @Sendable (Double?) -> Void) async throws -> [TranscriptSegment] {
        if let error { throw error }
        return segments
    }
}

struct FakeDiarizer: Diarizer {
    var turns: [SpeakerTurn] = [SpeakerTurn(start: 0, end: 5, speakerID: "S1")]
    func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn] { turns }
}

struct FakeProvider: MinutesProvider {
    let id: ProviderID = .openAI
    var chunks: [String] = ["# Minutes", " body"]
    var usage = UsageStats(inputTokens: 10, outputTokens: 5)
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        let chunks = chunks, usage = usage
        return AsyncThrowingStream { c in
            for chunk in chunks { c.yield(.textDelta(chunk)) }
            c.yield(.completed(usage))
            c.finish()
        }
    }
    func listModels(apiKey: String?) async throws -> [String] { [] }
}

func fixtureConfig(diarize: Bool, files: Int = 1) throws -> PipelineConfig {
    var urls: [URL] = []
    for i in 0..<files {
        urls.append(try makeWavFixture(seconds: 1.0, name: "pipe\(i)"))
    }
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-pipe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    return PipelineConfig(
        sourceFiles: urls, workDirectory: work, language: .english, diarize: diarize,
        template: TemplateContent(name: "T", systemPrompt: "sys", sections: ["Summary"]),
        model: "m")
}

@Test func fullRunEmitsOrderedEvents() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    var events: [PipelineEvent] = []
    for try await event in coordinator.run(try fixtureConfig(diarize: true)) {
        events.append(event)
    }
    // combined → transcribed → diarized → minutes
    var sawCombined = false, sawTranscribed = false, sawDiarized = false
    var markdown = ""
    var finalUsage: UsageStats?
    for event in events {
        switch event {
        case .combined: sawCombined = true
        case .transcribed(let segs, _):
            sawTranscribed = true
            #expect(segs.first?.text == "hello world")
        case .diarized(let segs):
            sawDiarized = true
            #expect(segs.first?.speaker == "S1")
        case .minutesDelta(let d): markdown += d
        case .minutesCompleted(let md, let usage, _):
            #expect(md == "# Minutes body")
            finalUsage = usage
        case .stageChanged: break
        }
    }
    #expect(sawCombined && sawTranscribed && sawDiarized)
    #expect(markdown == "# Minutes body")
    #expect(finalUsage?.totalTokens == 15)
}

@Test func skipsDiarizationWhenOff() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    var sawDiarized = false
    for try await event in coordinator.run(try fixtureConfig(diarize: false)) {
        if case .diarized = event { sawDiarized = true }
    }
    #expect(!sawDiarized)
}

@Test func transcriptionFailureCarriesStage() async throws {
    let engine = FakeEngine(segments: [], error: .failed("boom"))
    let coordinator = PipelineCoordinator(engine: engine, diarizer: FakeDiarizer(), provider: FakeProvider())
    do {
        for try await _ in coordinator.run(try fixtureConfig(diarize: false)) {}
        Issue.record("expected throw")
    } catch let error as PipelineError {
        #expect(error.stage == .transcribing)
    }
}

@Test func generateOnlySkipsAudioStages() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    let segments = [TranscriptSegment(start: 0, end: 1, text: "cached", speaker: "S1")]
    var sawCombined = false
    var markdown = ""
    for try await event in coordinator.generateOnly(try fixtureConfig(diarize: true), segments: segments, diarized: true) {
        switch event {
        case .combined: sawCombined = true
        case .minutesCompleted(let md, _, _): markdown = md
        default: break
        }
    }
    #expect(!sawCombined)
    #expect(markdown == "# Minutes body")
}

import Foundation

public enum PipelineStage: String, Sendable {
    case combining, transcribing, diarizing, generating
}

public enum PipelineEvent: Sendable {
    case stageChanged(PipelineStage)
    case combined(url: URL, duration: TimeInterval)
    case transcribed(segments: [TranscriptSegment], wallTime: TimeInterval)
    case diarized(segments: [TranscriptSegment])
    case minutesDelta(String)
    case minutesCompleted(markdown: String, usage: UsageStats, latency: TimeInterval)
}

public struct PipelineError: Error {
    public let stage: PipelineStage
    public let underlying: Error
}

public struct PipelineConfig: Sendable {
    public var sourceFiles: [URL]
    public var workDirectory: URL
    public var language: MeetingLanguage
    public var diarize: Bool
    public var template: TemplateContent
    public var speakerNames: [String: String]
    public var model: String
    public var apiKey: String?
    public var outputLanguage: MinutesLanguage

    public init(sourceFiles: [URL], workDirectory: URL, language: MeetingLanguage,
                diarize: Bool, template: TemplateContent,
                speakerNames: [String: String] = [:], model: String, apiKey: String? = nil,
                outputLanguage: MinutesLanguage = .matchTranscript) {
        self.sourceFiles = sourceFiles
        self.workDirectory = workDirectory
        self.language = language
        self.diarize = diarize
        self.template = template
        self.speakerNames = speakerNames
        self.model = model
        self.apiKey = apiKey
        self.outputLanguage = outputLanguage
    }
}

public struct PipelineCoordinator: Sendable {
    let engine: TranscriptionEngine
    let diarizer: Diarizer
    let provider: MinutesProvider

    public init(engine: TranscriptionEngine, diarizer: Diarizer, provider: MinutesProvider) {
        self.engine = engine
        self.diarizer = diarizer
        self.provider = provider
    }

    private func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds)
             + Double(duration.components.attoseconds) / 1e18
    }

    public func run(_ config: PipelineConfig) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // 1. Combine
                    continuation.yield(.stageChanged(.combining))
                    let combinedURL = config.workDirectory.appendingPathComponent("combined.m4a")
                    let duration: TimeInterval
                    do {
                        duration = try await AudioCombiner.combine(
                            fileURLs: config.sourceFiles, outputURL: combinedURL)
                    } catch {
                        throw PipelineError(stage: .combining, underlying: error)
                    }
                    continuation.yield(.combined(url: combinedURL, duration: duration))

                    // 2. Transcribe
                    continuation.yield(.stageChanged(.transcribing))
                    var segments: [TranscriptSegment]
                    let started = ContinuousClock.now
                    do {
                        try await engine.prepare(language: config.language)
                        segments = try await engine.transcribe(
                            fileURL: combinedURL, language: config.language, onProgress: { _ in })
                    } catch {
                        throw PipelineError(stage: .transcribing, underlying: error)
                    }
                    let wallTime = elapsedSeconds(since: started)
                    continuation.yield(.transcribed(segments: segments, wallTime: wallTime))

                    // 3. Diarize (optional)
                    if config.diarize {
                        continuation.yield(.stageChanged(.diarizing))
                        do {
                            let turns = try await diarizer.speakerTurns(fileURL: combinedURL)
                            segments = SpeakerMerger.merge(segments: segments, turns: turns)
                        } catch {
                            throw PipelineError(stage: .diarizing, underlying: error)
                        }
                        continuation.yield(.diarized(segments: segments))
                    }

                    // 4. Generate
                    try await generate(config: config, segments: segments,
                                       diarized: config.diarize, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func generateOnly(
        _ config: PipelineConfig, segments: [TranscriptSegment], diarized: Bool
    ) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await generate(config: config, segments: segments,
                                       diarized: diarized, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(
        config: PipelineConfig, segments: [TranscriptSegment], diarized: Bool,
        continuation: AsyncThrowingStream<PipelineEvent, Error>.Continuation
    ) async throws {
        continuation.yield(.stageChanged(.generating))
        let (system, user) = PromptBuilder.build(
            template: config.template, transcript: segments,
            speakerNames: config.speakerNames, diarized: diarized,
            outputLanguage: config.outputLanguage)
        let request = MinutesRequest(
            systemPrompt: system, userPrompt: user, model: config.model, apiKey: config.apiKey)
        let started = ContinuousClock.now
        var markdown = ""
        var usage = UsageStats(inputTokens: 0, outputTokens: 0)
        do {
            for try await event in try await provider.generate(request) {
                switch event {
                case .textDelta(let delta):
                    markdown += delta
                    continuation.yield(.minutesDelta(delta))
                case .completed(let stats):
                    usage = stats
                }
            }
        } catch {
            throw PipelineError(stage: .generating, underlying: error)
        }
        let latency = elapsedSeconds(since: started)
        continuation.yield(.minutesCompleted(markdown: markdown, usage: usage, latency: latency))
    }
}

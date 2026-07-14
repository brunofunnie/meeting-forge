import Foundation
import Observation
import SwiftData
import MeetingForgeCore

@Observable @MainActor
final class MeetingRunViewModel {
    enum RunState: Equatable {
        case idle
        case running(stage: PipelineStage)
        case failed(stage: PipelineStage?, message: String)
        case done
    }

    var state: RunState = .idle
    var liveMarkdown = ""
    var meetingID: PersistentIdentifier?

    func start(
        title: String, files: [URL], language: MeetingLanguage, diarize: Bool,
        template: MeetingTemplate, provider: ProviderID, model: String,
        settings: SettingsStore, context: ModelContext
    ) {
        let meeting = Meeting(title: title, language: language)
        let meetingUUID = UUID()
        let audioDir = AppPaths.audioDirectory(meetingID: meetingUUID)

        // Copy sources into the meeting folder so history owns its audio.
        var copiedFiles: [URL] = []
        for file in files {
            let dest = audioDir.appendingPathComponent("source").appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: file, to: dest)
                copiedFiles.append(dest)
            } catch {
                state = .failed(stage: nil, message: "Cannot copy \(file.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }
        meeting.sourceFileNames = copiedFiles.map(\.lastPathComponent)
        meeting.status = .transcribing
        context.insert(meeting)
        try? context.save()
        meetingID = meeting.persistentModelID

        let config = PipelineConfig(
            sourceFiles: copiedFiles,
            workDirectory: audioDir,
            language: language,
            diarize: diarize,
            template: TemplateContent(
                name: template.name, systemPrompt: template.systemPrompt, sections: template.sections),
            model: model,
            apiKey: settings.apiKey(for: provider))
        let coordinator = PipelineCoordinator(
            engine: settings.makeEngine(),
            diarizer: FluidAudioDiarizer(),
            provider: settings.makeProvider(provider))
        let calculator = settings.costCalculator()

        liveMarkdown = ""
        state = .running(stage: .combining)

        Task {
            do {
                for try await event in coordinator.run(config) {
                    switch event {
                    case .stageChanged(let stage):
                        state = .running(stage: stage)
                        meeting.status = stage == .generating ? .generating : .transcribing
                    case .combined(let url, let duration):
                        meeting.combinedAudioPath = url.path
                        meeting.durationSeconds = duration
                    case .transcribed(let segments, let wallTime):
                        let transcript = Transcript(engine: settings.engineID, diarized: diarize)
                        try transcript.setSegments(segments)
                        transcript.wallTimeSeconds = wallTime
                        meeting.transcript = transcript
                    case .diarized(let segments):
                        try meeting.transcript?.setSegments(segments)
                    case .minutesDelta(let delta):
                        liveMarkdown += delta
                    case .minutesCompleted(let markdown, let usage, let latency):
                        let run = MinutesRun(
                            provider: provider, modelName: model, templateName: template.name,
                            markdown: markdown,
                            inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                            costUSD: calculator.cost(model: model, usage: usage) ?? 0,
                            latencySeconds: latency)
                        meeting.minutesRuns.append(run)
                    }
                    try? context.save()
                }
                meeting.status = .done
                try? context.save()
                state = .done
            } catch let error as PipelineError {
                meeting.status = .failed
                try? context.save()
                state = .failed(stage: error.stage, message: describe(error.underlying))
            } catch {
                meeting.status = .failed
                try? context.save()
                state = .failed(stage: nil, message: describe(error))
            }
        }
    }

    /// Regenerate minutes for an existing meeting (retry, other provider/model/template).
    func regenerate(
        meeting: Meeting, template: MeetingTemplate, provider: ProviderID, model: String,
        settings: SettingsStore, context: ModelContext
    ) {
        guard let transcript = meeting.transcript,
              let segments = try? transcript.segments() else {
            state = .failed(stage: nil, message: "No transcript stored for this meeting.")
            return
        }
        let config = PipelineConfig(
            sourceFiles: [], workDirectory: FileManager.default.temporaryDirectory,
            language: meeting.language, diarize: transcript.diarized,
            template: TemplateContent(
                name: template.name, systemPrompt: template.systemPrompt, sections: template.sections),
            speakerNames: (try? transcript.speakerNames()) ?? [:],
            model: model, apiKey: settings.apiKey(for: provider))
        let coordinator = PipelineCoordinator(
            engine: settings.makeEngine(), diarizer: FluidAudioDiarizer(),
            provider: settings.makeProvider(provider))
        let calculator = settings.costCalculator()

        liveMarkdown = ""
        state = .running(stage: .generating)
        meeting.status = .generating
        Task {
            do {
                for try await event in coordinator.generateOnly(
                    config, segments: segments, diarized: transcript.diarized) {
                    switch event {
                    case .minutesDelta(let delta): liveMarkdown += delta
                    case .minutesCompleted(let markdown, let usage, let latency):
                        let run = MinutesRun(
                            provider: provider, modelName: model, templateName: template.name,
                            markdown: markdown,
                            inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                            costUSD: calculator.cost(model: model, usage: usage) ?? 0,
                            latencySeconds: latency)
                        meeting.minutesRuns.append(run)
                    default: break
                    }
                }
                meeting.status = .done
                try? context.save()
                state = .done
            } catch {
                meeting.status = .done // transcript still valid; only this run failed
                try? context.save()
                state = .failed(stage: .generating, message: describe(error))
            }
        }
    }

    private func describe(_ error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingAPIKey(let id): return "\(id.displayName): API key missing — add it in Settings."
            case .http(let status, let message): return "HTTP \(status): \(message)"
            case .malformedResponse(let detail): return "Malformed response: \(detail)"
            case .executableNotFound(let detail): return detail
            case .cliFailure(let detail): return "Claude Code failed: \(detail)"
            }
        }
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .assetUnavailable(let detail): return "Speech assets unavailable: \(detail)"
            case .modelNotDownloaded(let model): return "Whisper model \(model) not downloaded — get it in Settings."
            case .failed(let detail): return "Transcription failed: \(detail)"
            }
        }
        return String(describing: error)
    }
}

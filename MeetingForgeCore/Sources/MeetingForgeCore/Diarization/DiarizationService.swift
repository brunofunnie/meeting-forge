import Foundation
import FluidAudio

public protocol Diarizer: Sendable {
    /// Returns speaker turns for the audio file, speakers labeled "S1", "S2", ...
    func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn]
}

public enum DiarizationError: Error {
    case failed(String)
}

public final class FluidAudioDiarizer: Diarizer {
    public init() {}

    public func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn] {
        do {
            // Models download on first use to FluidAudio's cache dir.
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)

            let samples = try AudioConverter().resampleAudioFile(fileURL)  // 16kHz mono Float
            let result = try diarizer.performCompleteDiarization(samples)

            // Map FluidAudio speaker ids (arbitrary strings) to stable "S1","S2",... by first appearance.
            var idMap: [String: String] = [:]
            var turns: [SpeakerTurn] = []
            for segment in result.segments {
                let rawID = String(describing: segment.speakerId)
                if idMap[rawID] == nil {
                    idMap[rawID] = "S\(idMap.count + 1)"
                }
                turns.append(
                    SpeakerTurn(
                        start: TimeInterval(segment.startTimeSeconds),
                        end: TimeInterval(segment.endTimeSeconds),
                        speakerID: idMap[rawID]!
                    ))
            }
            return turns.sorted { $0.start < $1.start }
        } catch let error as DiarizationError {
            throw error
        } catch {
            throw DiarizationError.failed(String(describing: error))
        }
    }
}

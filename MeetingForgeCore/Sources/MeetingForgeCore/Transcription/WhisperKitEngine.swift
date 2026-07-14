import Foundation
import WhisperKit

public final class WhisperKitModelManager: Sendable {
    public let modelsDirectory: URL

    public static let recommendedModels: [String] = [
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-large-v3-v20240930_626MB",
        "openai_whisper-large-v3-turbo",
    ]

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public func downloadedModels() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path))?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
    }

    public func isDownloaded(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(name).path)
    }

    public func download(_ name: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(
            variant: name,
            downloadBase: modelsDirectory,
            progressCallback: { progress($0.fractionCompleted) }
        )
    }

    public func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: modelsDirectory.appendingPathComponent(name))
    }
}

public final class WhisperKitEngine: TranscriptionEngine {
    public let id: TranscriptionEngineID = .whisperKit
    private let modelName: String
    private let manager: WhisperKitModelManager

    public init(modelName: String, modelsDirectory: URL) {
        self.modelName = modelName
        self.manager = WhisperKitModelManager(modelsDirectory: modelsDirectory)
    }

    public func prepare(language: MeetingLanguage) async throws {
        guard manager.isDownloaded(modelName) else {
            throw TranscriptionError.modelNotDownloaded(modelName)
        }
    }

    public func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        guard manager.isDownloaded(modelName) else {
            throw TranscriptionError.modelNotDownloaded(modelName)
        }
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: manager.modelsDirectory,
            download: false
        )
        let pipe: WhisperKit
        do {
            pipe = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.failed(String(describing: error))
        }

        var options = DecodingOptions()
        switch language {
        case .portugueseBR: options.language = "pt"; options.detectLanguage = false
        case .english: options.language = "en"; options.detectLanguage = false
        case .auto: options.detectLanguage = true
        }

        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(
                audioPath: fileURL.path,
                decodeOptions: options,
                callback: { progress in
                    onProgress(nil) // WhisperKit callback ticks per segment; indeterminate
                    return nil
                }
            )
        } catch {
            throw TranscriptionError.failed(String(describing: error))
        }

        return results.flatMap { result in
            result.segments.map { seg in
                TranscriptSegment(
                    start: TimeInterval(seg.start),
                    end: TimeInterval(seg.end),
                    text: seg.text.trimmingCharacters(in: .whitespaces)
                )
            }
        }
    }
}

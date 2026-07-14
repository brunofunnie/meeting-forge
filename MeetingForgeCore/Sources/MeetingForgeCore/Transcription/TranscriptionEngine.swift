import Foundation

public enum TranscriptionError: Error {
    /// Apple Speech assets for the locale missing or not installable.
    case assetUnavailable(String)
    /// WhisperKit model selected but not downloaded yet.
    case modelNotDownloaded(String)
    case failed(String)
}

public protocol TranscriptionEngine: Sendable {
    var id: TranscriptionEngineID { get }
    /// Ensure models/assets for the language are present (may download).
    func prepare(language: MeetingLanguage) async throws
    /// Transcribe a single audio file into timed segments.
    /// onProgress receives 0...1 when determinable, nil for indeterminate ticks.
    func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment]
}

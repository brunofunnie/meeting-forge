import Foundation
import Speech
import AVFoundation
import NaturalLanguage

public final class AppleSpeechEngine: TranscriptionEngine {
    public let id: TranscriptionEngineID = .appleSpeech

    public init() {}

    public func prepare(language: MeetingLanguage) async throws {
        // Assets are ensured per-run in transcribe(); auto needs both locales available.
        let locales = language == .auto ? ["pt_BR", "en_US"] : [language.localeIdentifier!]
        for identifier in locales {
            let transcriber = SpeechTranscriber(
                locale: Locale(identifier: identifier),
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }

    public func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let resolved = try await resolveLanguage(language, fileURL: fileURL)
        return try await run(fileURL: fileURL, localeIdentifier: resolved, onProgress: onProgress)
    }

    /// For .auto: transcribe the first ~30s in English, classify with
    /// NLLanguageRecognizer, then run the full pass in the detected language.
    private func resolveLanguage(_ language: MeetingLanguage, fileURL: URL) async throws -> String {
        if let identifier = language.localeIdentifier { return identifier }
        let probeSegments = try await run(
            fileURL: fileURL, localeIdentifier: "en_US",
            limitSeconds: 30, onProgress: { _ in }
        )
        let probeText = probeSegments.map(\.text).joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.portuguese, .english]
        recognizer.processString(probeText)
        return recognizer.dominantLanguage == .portuguese ? "pt_BR" : "en_US"
    }

    private func run(
        fileURL: URL,
        localeIdentifier: String,
        limitSeconds: Double? = nil,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)
        let totalSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        let effectiveTotal = limitSeconds.map { min($0, totalSeconds) } ?? totalSeconds

        // Collect results concurrently with feeding the file.
        let collector = Task<[TranscriptSegment], Error> {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                let range = result.range
                let start = range.start.seconds
                let end = range.end.seconds
                if let limit = limitSeconds, start > limit { break }
                segments.append(TranscriptSegment(start: start, end: end, text: text))
                if effectiveTotal > 0 { onProgress(min(end / effectiveTotal, 1.0)) }
            }
            return segments
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw TranscriptionError.failed(String(describing: error))
        }
        return try await collector.value
    }
}

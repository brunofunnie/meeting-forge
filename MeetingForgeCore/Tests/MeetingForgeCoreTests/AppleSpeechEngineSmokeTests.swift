import Testing
import Foundation
@testable import MeetingForgeCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["MF_SMOKE_AUDIO"] != nil))
func transcribesRealAudioFile() async throws {
    // export MF_SMOKE_AUDIO=/path/to/short-speech.m4a before running
    let path = ProcessInfo.processInfo.environment["MF_SMOKE_AUDIO"]!
    let engine = AppleSpeechEngine()
    try await engine.prepare(language: .english)
    let segments = try await engine.transcribe(
        fileURL: URL(fileURLWithPath: path), language: .english, onProgress: { _ in })
    #expect(!segments.isEmpty)
    #expect(segments.allSatisfy { $0.end >= $0.start })
}

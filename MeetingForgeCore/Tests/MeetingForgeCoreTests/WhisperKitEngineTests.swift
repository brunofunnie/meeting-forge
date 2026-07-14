import Testing
import Foundation
@testable import MeetingForgeCore

@Test func modelManagerListsDownloadedModels() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-wk-\(UUID().uuidString)")
    let manager = WhisperKitModelManager(modelsDirectory: dir)
    #expect(manager.downloadedModels().isEmpty)

    // Simulate a completed download: WhisperKit stores each model as a folder.
    let modelDir = dir.appendingPathComponent("openai_whisper-base")
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    #expect(manager.downloadedModels() == ["openai_whisper-base"])
    #expect(manager.isDownloaded("openai_whisper-base"))
    #expect(!manager.isDownloaded("openai_whisper-large-v3-v20240930_626MB"))

    try manager.delete("openai_whisper-base")
    #expect(manager.downloadedModels().isEmpty)
}

@Test func engineRefusesToRunWithoutDownloadedModel() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-wk-\(UUID().uuidString)")
    let engine = WhisperKitEngine(modelName: "openai_whisper-base", modelsDirectory: dir)
    await #expect(throws: TranscriptionError.self) {
        try await engine.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/nothing.m4a"),
            language: .english, onProgress: { _ in })
    }
}

@Test func recommendedModelsNonEmpty() {
    #expect(WhisperKitModelManager.recommendedModels.contains("openai_whisper-base"))
}

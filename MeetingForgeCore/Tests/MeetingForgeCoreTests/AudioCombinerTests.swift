import Testing
import Foundation
import AVFoundation
@testable import MeetingForgeCore

/// Writes a mono 16kHz sine-wave WAV of the given duration and returns its URL.
func makeWavFixture(seconds: Double, frequency: Double = 440, name: String) throws -> URL {
    let sampleRate = 16_000.0
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-fixture-\(name)-\(UUID().uuidString).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        data[i] = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate)) * 0.5
    }
    try file.write(from: buffer)
    return url
}

@Test func combinesTwoFilesInOrder() async throws {
    let a = try makeWavFixture(seconds: 2.0, name: "a")
    let b = try makeWavFixture(seconds: 3.0, name: "b")
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-combined-\(UUID().uuidString).m4a")

    let duration = try await AudioCombiner.combine(fileURLs: [a, b], outputURL: out)

    #expect(abs(duration - 5.0) < 0.2)
    let asset = AVURLAsset(url: out)
    let assetDuration = try await asset.load(.duration).seconds
    #expect(abs(assetDuration - 5.0) < 0.2)
}

@Test func singleFileStillExports() async throws {
    let a = try makeWavFixture(seconds: 1.5, name: "solo")
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-single-\(UUID().uuidString).m4a")
    let duration = try await AudioCombiner.combine(fileURLs: [a], outputURL: out)
    #expect(abs(duration - 1.5) < 0.2)
    #expect(FileManager.default.fileExists(atPath: out.path))
}

@Test func emptyInputThrows() async {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("x.m4a")
    await #expect(throws: AudioCombinerError.noInput) {
        _ = try await AudioCombiner.combine(fileURLs: [], outputURL: out)
    }
}

@Test func undecodableFileThrows() async throws {
    let junk = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-junk-\(UUID().uuidString).mp3")
    try Data("not audio at all".utf8).write(to: junk)
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("y.m4a")
    await #expect(throws: AudioCombinerError.self) {
        _ = try await AudioCombiner.combine(fileURLs: [junk], outputURL: out)
    }
}

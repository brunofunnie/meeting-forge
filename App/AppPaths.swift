import Foundation

enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingForge")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func audioDirectory(meetingID: UUID) -> URL {
        let dir = root.appendingPathComponent("audio").appendingPathComponent(meetingID.uuidString)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("source"), withIntermediateDirectories: true)
        return dir
    }

    static var whisperModelsDirectory: URL {
        root.appendingPathComponent("whisper-models")
    }
}

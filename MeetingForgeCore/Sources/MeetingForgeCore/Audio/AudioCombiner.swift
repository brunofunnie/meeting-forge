import Foundation
import AVFoundation

public enum AudioCombinerError: Error, Equatable {
    case noInput
    case undecodable(URL)
    case exportFailed(String)
}

public enum AudioCombiner {
    /// Concatenates the given audio files in order into a single AAC .m4a file.
    /// Returns the total duration in seconds.
    public static func combine(fileURLs: [URL], outputURL: URL) async throws -> TimeInterval {
        guard !fileURLs.isEmpty else { throw AudioCombinerError.noInput }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AudioCombinerError.exportFailed("cannot create composition track") }

        var cursor = CMTime.zero
        for url in fileURLs {
            let asset = AVURLAsset(url: url)
            let duration: CMTime
            let sourceTracks: [AVAssetTrack]
            do {
                duration = try await asset.load(.duration)
                sourceTracks = try await asset.loadTracks(withMediaType: .audio)
            } catch {
                throw AudioCombinerError.undecodable(url)
            }
            guard let sourceTrack = sourceTracks.first, duration.seconds > 0 else {
                throw AudioCombinerError.undecodable(url)
            }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, duration)
        }

        // Export atomically: write to a temp file next to outputURL and only move it
        // into place on success, so a failed export never destroys a previous output.
        let tmpURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".mf-export-\(UUID().uuidString).m4a")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCombinerError.exportFailed("cannot create export session")
        }
        do {
            try await export.export(to: tmpURL, as: .m4a)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: outputURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw AudioCombinerError.exportFailed(String(describing: error))
        }
        return cursor.seconds
    }
}

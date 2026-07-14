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

        try? FileManager.default.removeItem(at: outputURL)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCombinerError.exportFailed("cannot create export session")
        }
        do {
            try await export.export(to: outputURL, as: .m4a)
        } catch {
            throw AudioCombinerError.exportFailed(String(describing: error))
        }
        return cursor.seconds
    }
}

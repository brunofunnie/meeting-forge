import Foundation

public enum SpeakerMerger {
    /// Assigns a speaker to each transcript segment from diarization turns.
    /// Max time-overlap wins; zero-overlap segments take the nearest turn
    /// by midpoint-to-interval distance. Empty turns → unchanged segments.
    public static func merge(segments: [TranscriptSegment], turns: [SpeakerTurn]) -> [TranscriptSegment] {
        guard !turns.isEmpty else { return segments }
        return segments.map { segment in
            var segment = segment
            segment.speaker = bestSpeaker(for: segment, in: turns)
            return segment
        }
    }

    private static func bestSpeaker(for segment: TranscriptSegment, in turns: [SpeakerTurn]) -> String {
        var bestOverlap: TimeInterval = 0
        var bestByOverlap: String?
        for turn in turns {
            let overlap = min(segment.end, turn.end) - max(segment.start, turn.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestByOverlap = turn.speakerID
            }
        }
        if let winner = bestByOverlap { return winner }

        let midpoint = (segment.start + segment.end) / 2
        let nearest = turns.min { distance(from: midpoint, to: $0) < distance(from: midpoint, to: $1) }!
        return nearest.speakerID
    }

    private static func distance(from point: TimeInterval, to turn: SpeakerTurn) -> TimeInterval {
        if point < turn.start { return turn.start - point }
        if point > turn.end { return point - turn.end }
        return 0
    }
}

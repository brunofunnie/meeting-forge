import Testing
@testable import MeetingForgeCore

@Test func assignsSpeakerByMaxOverlap() {
    let segments = [
        TranscriptSegment(start: 0, end: 4, text: "hello everyone"),
        TranscriptSegment(start: 4, end: 8, text: "hi bruno"),
    ]
    let turns = [
        SpeakerTurn(start: 0, end: 4.5, speakerID: "S1"),
        SpeakerTurn(start: 4.5, end: 8, speakerID: "S2"),
    ]
    let merged = SpeakerMerger.merge(segments: segments, turns: turns)
    #expect(merged[0].speaker == "S1")
    #expect(merged[1].speaker == "S2") // 3.5s overlap with S2 beats 0.5s with S1
}

@Test func segmentSpanningTwoTurnsTakesLargerShare() {
    let segments = [TranscriptSegment(start: 2, end: 6, text: "crossing")]
    let turns = [
        SpeakerTurn(start: 0, end: 3, speakerID: "S1"),   // 1s overlap
        SpeakerTurn(start: 3, end: 10, speakerID: "S2"),  // 3s overlap
    ]
    #expect(SpeakerMerger.merge(segments: segments, turns: turns)[0].speaker == "S2")
}

@Test func gapSegmentFallsBackToNearestTurn() {
    let segments = [TranscriptSegment(start: 10, end: 11, text: "in a gap")]
    let turns = [
        SpeakerTurn(start: 0, end: 5, speakerID: "S1"),
        SpeakerTurn(start: 20, end: 30, speakerID: "S2"),
    ]
    // midpoint 10.5: distance to S1 interval = 5.5, to S2 = 9.5 → S1
    #expect(SpeakerMerger.merge(segments: segments, turns: turns)[0].speaker == "S1")
}

@Test func emptyTurnsLeavesSegmentsUntouched() {
    let segments = [TranscriptSegment(start: 0, end: 1, text: "solo")]
    let merged = SpeakerMerger.merge(segments: segments, turns: [])
    #expect(merged == segments)
}

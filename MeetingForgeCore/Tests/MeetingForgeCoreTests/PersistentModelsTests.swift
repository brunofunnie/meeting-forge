import Testing
import Foundation
import SwiftData
@testable import MeetingForgeCore

@MainActor
@Test func meetingGraphPersists() throws {
    let container = try ModelContainer(
        for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let meeting = Meeting(title: "Sprint Planning", language: .portugueseBR)
    meeting.sourceFileNames = ["a.m4a", "b.m4a"]
    let transcript = Transcript(engine: .appleSpeech, diarized: true)
    try transcript.setSegments([TranscriptSegment(start: 0, end: 1, text: "olá", speaker: "S1")])
    meeting.transcript = transcript
    let run = MinutesRun(provider: .anthropic, modelName: "claude-sonnet-4-5",
                         templateName: "Business", markdown: "# Ata",
                         inputTokens: 100, outputTokens: 50, costUSD: 0.01, latencySeconds: 3.2)
    meeting.minutesRuns.append(run)
    ctx.insert(meeting)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Meeting>())
    #expect(fetched.count == 1)
    #expect(fetched[0].status == .pending)
    #expect(try fetched[0].transcript?.segments().first?.text == "olá")
    #expect(fetched[0].minutesRuns.first?.totalTokens == 150)
}

@MainActor
@Test func speakerRenamesPersist() throws {
    let container = try ModelContainer(
        for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let transcript = Transcript(engine: .whisperKit, diarized: true)
    try transcript.setSpeakerNames(["S1": "Bruno", "S2": "Ana"])
    container.mainContext.insert(transcript)
    #expect(try transcript.speakerNames()["S1"] == "Bruno")
}

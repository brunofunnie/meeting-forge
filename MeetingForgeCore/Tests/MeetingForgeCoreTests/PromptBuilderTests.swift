import Testing
@testable import MeetingForgeCore

let template = TemplateContent(
    name: "Business",
    systemPrompt: "You are an expert minute-taker.",
    sections: ["Summary", "Action Points", "Questions"]
)

@Test func systemPromptContainsSectionsAndLanguageRule() {
    let (system, _) = PromptBuilder.build(template: template, transcript: [], speakerNames: [:], diarized: false)
    #expect(system.contains("You are an expert minute-taker."))
    #expect(system.contains("Summary"))
    #expect(system.contains("Action Points"))
    #expect(system.contains("same language as the transcript"))
}

@Test func diarizedTranscriptUsesRenamedSpeakers() {
    let segments = [
        TranscriptSegment(start: 0, end: 2, text: "bom dia", speaker: "S1"),
        TranscriptSegment(start: 62, end: 65, text: "olá", speaker: "S2"),
    ]
    let (_, user) = PromptBuilder.build(
        template: template, transcript: segments,
        speakerNames: ["S1": "Bruno"], diarized: true)
    #expect(user.contains("[00:00] Bruno: bom dia"))
    #expect(user.contains("[01:02] S2: olá")) // unrenamed falls back to raw ID
}

@Test func plainTranscriptOmitsSpeakers() {
    let segments = [TranscriptSegment(start: 125, end: 130, text: "next topic", speaker: "S1")]
    let (_, user) = PromptBuilder.build(template: template, transcript: segments, speakerNames: [:], diarized: false)
    #expect(user.contains("[02:05] next topic"))
    #expect(!user.contains("S1"))
}

@Test func explicitPortugueseOutputOverridesTranscriptLanguage() {
    let (system, _) = PromptBuilder.build(
        template: template, transcript: [], speakerNames: [:], diarized: false,
        outputLanguage: .portugueseBR)
    #expect(system.contains("Brazilian Portuguese"))
    #expect(!system.contains("same language as the transcript"))
}

@Test func explicitEnglishOutputOverridesTranscriptLanguage() {
    let (system, _) = PromptBuilder.build(
        template: template, transcript: [], speakerNames: [:], diarized: false,
        outputLanguage: .english)
    #expect(system.contains("Write the minutes in English"))
    #expect(!system.contains("same language as the transcript"))
}

@Test func defaultOutputLanguageMatchesTranscript() {
    let (system, _) = PromptBuilder.build(
        template: template, transcript: [], speakerNames: [:], diarized: false)
    #expect(system.contains("same language as the transcript"))
}

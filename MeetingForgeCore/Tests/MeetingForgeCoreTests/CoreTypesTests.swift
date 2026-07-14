import Testing
import Foundation
@testable import MeetingForgeCore

@Test func languageLocales() {
    #expect(MeetingLanguage.portugueseBR.localeIdentifier == "pt_BR")
    #expect(MeetingLanguage.english.localeIdentifier == "en_US")
    #expect(MeetingLanguage.auto.localeIdentifier == nil)
    #expect(MeetingLanguage(rawValue: "pt-BR") == .portugueseBR)
}

@Test func usageStatsTotals() {
    let u = UsageStats(inputTokens: 1200, outputTokens: 300, reportedCostUSD: nil)
    #expect(u.totalTokens == 1500)
}

@Test func segmentRoundTripsJSON() throws {
    let seg = TranscriptSegment(start: 0.5, end: 2.0, text: "hello", speaker: "S1")
    let data = try JSONEncoder().encode([seg])
    let back = try JSONDecoder().decode([TranscriptSegment].self, from: data)
    #expect(back == [seg])
}

@Test func providerDisplayNames() {
    #expect(ProviderID.openAI.displayName == "OpenAI")
    #expect(ProviderID.claudeCode.displayName == "Claude Code")
    #expect(ProviderID.ollamaLocal.displayName == "Ollama (local)")
    #expect(ProviderID.allCases.count == 6)
    #expect(!ProviderID.ollamaLocal.requiresAPIKey)
    #expect(!ProviderID.claudeCode.requiresAPIKey)
    #expect(ProviderID.ollamaCloud.requiresAPIKey)
}

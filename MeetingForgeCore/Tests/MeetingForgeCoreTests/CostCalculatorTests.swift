import Testing
@testable import MeetingForgeCore

@Test func reportedCostWins() {
    let calc = CostCalculator()
    let usage = UsageStats(inputTokens: 1_000_000, outputTokens: 0, reportedCostUSD: 0.5)
    #expect(calc.cost(model: "whatever", usage: usage) == 0.5)
}

@Test func prefixMatchComputesCost() {
    let calc = CostCalculator(overrides: ["gpt-5.2": ModelPrice(inputPerMTok: 2.0, outputPerMTok: 8.0)])
    let usage = UsageStats(inputTokens: 500_000, outputTokens: 250_000)
    // 0.5 * 2.0 + 0.25 * 8.0 = 3.0
    #expect(calc.cost(model: "gpt-5.2-2026-06-01", usage: usage) == 3.0)
}

@Test func longestPrefixWins() {
    let calc = CostCalculator(overrides: [
        "claude": ModelPrice(inputPerMTok: 1, outputPerMTok: 1),
        "claude-sonnet-4-5": ModelPrice(inputPerMTok: 3, outputPerMTok: 15),
    ])
    let usage = UsageStats(inputTokens: 1_000_000, outputTokens: 0)
    #expect(calc.cost(model: "claude-sonnet-4-5-20260101", usage: usage) == 3.0)
}

@Test func unknownModelReturnsNil() {
    let calc = CostCalculator(overrides: [:])
    // Wipe defaults influence by using a model name no default table entry prefixes.
    #expect(calc.cost(model: "totally-unknown-model-xyz",
                      usage: UsageStats(inputTokens: 10, outputTokens: 10)) == nil)
}

@Test func defaultTableCoversCommonModels() {
    #expect(CostCalculator.defaultPrices.keys.contains("gpt-5"))
    #expect(CostCalculator.defaultPrices.keys.contains("claude-sonnet-4-5"))
    #expect(CostCalculator.defaultPrices.keys.contains("gemini-2.5-pro"))
}

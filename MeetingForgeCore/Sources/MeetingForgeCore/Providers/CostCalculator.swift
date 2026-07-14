import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }
}

public struct CostCalculator: Sendable {
    /// Prefix-keyed price table (USD per million tokens). Longest matching prefix wins.
    public static let defaultPrices: [String: ModelPrice] = [
        // OpenAI
        "gpt-5": ModelPrice(inputPerMTok: 1.25, outputPerMTok: 10.0),
        "gpt-5-mini": ModelPrice(inputPerMTok: 0.25, outputPerMTok: 2.0),
        "gpt-4o": ModelPrice(inputPerMTok: 2.5, outputPerMTok: 10.0),
        // Anthropic
        "claude-sonnet-4-5": ModelPrice(inputPerMTok: 3.0, outputPerMTok: 15.0),
        "claude-haiku-4-5": ModelPrice(inputPerMTok: 1.0, outputPerMTok: 5.0),
        "claude-opus-4": ModelPrice(inputPerMTok: 15.0, outputPerMTok: 75.0),
        // Google
        "gemini-2.5-pro": ModelPrice(inputPerMTok: 1.25, outputPerMTok: 10.0),
        "gemini-2.5-flash": ModelPrice(inputPerMTok: 0.30, outputPerMTok: 2.5),
    ]

    let table: [String: ModelPrice]

    public init(overrides: [String: ModelPrice]? = nil) {
        if let overrides, !overrides.isEmpty {
            self.table = Self.defaultPrices.merging(overrides) { _, override in override }
                .merging(overrides) { existing, _ in existing }
        } else {
            self.table = Self.defaultPrices
        }
    }

    public func cost(model: String, usage: UsageStats) -> Double? {
        if let reported = usage.reportedCostUSD { return reported }
        let match = table.keys
            .filter { model.hasPrefix($0) }
            .max { $0.count < $1.count }
        guard let match, let price = table[match] else { return nil }
        return Double(usage.inputTokens) / 1_000_000 * price.inputPerMTok
             + Double(usage.outputTokens) / 1_000_000 * price.outputPerMTok
    }
}

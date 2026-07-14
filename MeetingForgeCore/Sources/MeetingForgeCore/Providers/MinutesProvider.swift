import Foundation

public struct MinutesRequest: Sendable {
    public var systemPrompt: String
    public var userPrompt: String
    public var model: String
    public var apiKey: String?

    public init(systemPrompt: String, userPrompt: String, model: String, apiKey: String? = nil) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.model = model
        self.apiKey = apiKey
    }
}

public enum MinutesEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(UsageStats)
}

public enum ProviderError: Error {
    case missingAPIKey(ProviderID)
    case http(status: Int, message: String)
    case malformedResponse(String)
    case executableNotFound(String)
    case cliFailure(String)
}

public protocol MinutesProvider: Sendable {
    var id: ProviderID { get }
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error>
    func listModels(apiKey: String?) async throws -> [String]
}

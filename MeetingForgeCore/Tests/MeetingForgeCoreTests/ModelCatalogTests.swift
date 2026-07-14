import Testing
import Foundation
@testable import MeetingForgeCore

/// MinutesProvider fake that counts listModels calls.
final class CountingProvider: MinutesProvider, @unchecked Sendable {
    let id: ProviderID = .openAI
    var calls = 0
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        fatalError("unused")
    }
    func listModels(apiKey: String?) async throws -> [String] {
        calls += 1
        return ["model-a", "model-b"]
    }
}

@Test func cachesModelList() async throws {
    let suite = "mf-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let catalog = ModelCatalog(defaults: defaults)
    let provider = CountingProvider()

    let first = try await catalog.models(for: provider, apiKey: "k", forceRefresh: false)
    let second = try await catalog.models(for: provider, apiKey: "k", forceRefresh: false)
    #expect(first == ["model-a", "model-b"])
    #expect(second == first)
    #expect(provider.calls == 1) // second came from cache

    _ = try await catalog.models(for: provider, apiKey: "k", forceRefresh: true)
    #expect(provider.calls == 2)
}

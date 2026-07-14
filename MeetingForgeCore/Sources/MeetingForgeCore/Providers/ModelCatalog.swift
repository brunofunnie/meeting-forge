import Foundation

public final class ModelCatalog: @unchecked Sendable {
    private let defaults: UserDefaults
    private let maxAge: TimeInterval

    public init(defaults: UserDefaults = .standard, maxAge: TimeInterval = 24 * 3600) {
        self.defaults = defaults
        self.maxAge = maxAge
    }

    private struct CacheEntry: Codable {
        var models: [String]
        var fetchedAt: Date
    }

    public func models(for provider: MinutesProvider, apiKey: String?, forceRefresh: Bool) async throws -> [String] {
        let key = "model-cache-\(provider.id.rawValue)"
        if !forceRefresh,
           let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
           Date.now.timeIntervalSince(entry.fetchedAt) < maxAge {
            return entry.models
        }
        let models = try await provider.listModels(apiKey: apiKey)
        let entry = CacheEntry(models: models, fetchedAt: .now)
        defaults.set(try? JSONEncoder().encode(entry), forKey: key)
        return models
    }
}

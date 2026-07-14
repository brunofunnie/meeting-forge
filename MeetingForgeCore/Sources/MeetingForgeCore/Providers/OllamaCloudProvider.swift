import Foundation

/// Talks to an Ollama server — the hosted cloud (Bearer auth) or a local
/// instance (no auth), selected via `id`/`baseURL`/`requiresAuth`.
public struct OllamaCloudProvider: MinutesProvider {
    public let id: ProviderID
    let transport: StreamTransport
    let baseURL: URL
    let requiresAuth: Bool

    public init(id: ProviderID = .ollamaCloud,
                transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://ollama.com")!,
                requiresAuth: Bool = true) {
        self.id = id
        self.transport = transport
        self.baseURL = baseURL
        self.requiresAuth = requiresAuth
    }

    /// Preconfigured provider for a local Ollama install.
    public static func local() -> OllamaCloudProvider {
        OllamaCloudProvider(id: .ollamaLocal,
                            baseURL: URL(string: "http://localhost:11434")!,
                            requiresAuth: false)
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        if requiresAuth, request.apiKey?.isEmpty != false {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        urlRequest.httpMethod = "POST"
        if let apiKey = request.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt],
            ],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var usage: UsageStats?
                do {
                    guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
                    for try await line in lines {
                        // Ollama streams raw JSON objects, one per line (no SSE framing).
                        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                        else { continue }
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if json["done"] as? Bool == true {
                            usage = UsageStats(
                                inputTokens: json["prompt_eval_count"] as? Int ?? 0,
                                outputTokens: json["eval_count"] as? Int ?? 0)
                        }
                    }
                    continuation.yield(.completed(usage ?? UsageStats(inputTokens: 0, outputTokens: 0)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        if requiresAuth, apiKey?.isEmpty != false {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return models.compactMap { $0["name"] as? String }
    }
}

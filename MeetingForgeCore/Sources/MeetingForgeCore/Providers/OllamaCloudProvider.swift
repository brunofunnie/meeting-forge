import Foundation

public struct OllamaCloudProvider: MinutesProvider {
    public let id: ProviderID = .ollamaCloud
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://ollama.com")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        guard let apiKey, !apiKey.isEmpty else { throw ProviderError.missingAPIKey(id) }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

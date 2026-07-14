import Foundation

public struct OpenAIProvider: MinutesProvider {
    public let id: ProviderID = .openAI
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "stream": true,
            "stream_options": ["include_usage": true],
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
                        guard let payload = SSEParser.payload(fromLine: line),
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
                        else { continue }
                        if let errorDict = json["error"] as? [String: Any] {
                            let message = errorDict["message"] as? String ?? payload
                            continuation.finish(throwing: ProviderError.malformedResponse("stream error: \(message)"))
                            return
                        }
                        if let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if let u = json["usage"] as? [String: Any],
                           let input = u["prompt_tokens"] as? Int,
                           let output = u["completion_tokens"] as? Int {
                            usage = UsageStats(inputTokens: input, outputTokens: output)
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
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("models"))
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return data.compactMap { $0["id"] as? String }
    }
}

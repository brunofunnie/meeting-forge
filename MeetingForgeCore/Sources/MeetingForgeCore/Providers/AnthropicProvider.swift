import Foundation

public struct AnthropicProvider: MinutesProvider {
    public let id: ProviderID = .anthropic
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://api.anthropic.com/v1")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "max_tokens": 8192,
            "stream": true,
            "system": request.systemPrompt,
            "messages": [["role": "user", "content": request.userPrompt]],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var inputTokens = 0
                var outputTokens = 0
                do {
                    guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
                    for try await line in lines {
                        guard let payload = SSEParser.payload(fromLine: line),
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let type = json["type"] as? String
                        else { continue }
                        switch type {
                        case "message_start":
                            if let message = json["message"] as? [String: Any],
                               let u = message["usage"] as? [String: Any] {
                                inputTokens = u["input_tokens"] as? Int ?? 0
                            }
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(.textDelta(text))
                            }
                        case "message_delta":
                            if let u = json["usage"] as? [String: Any],
                               let output = u["output_tokens"] as? Int {
                                outputTokens = output
                            }
                        case "error":
                            let message = (json["error"] as? [String: Any])?["message"] as? String ?? payload
                            continuation.finish(throwing: ProviderError.malformedResponse("stream error: \(message)"))
                            return
                        default:
                            break
                        }
                    }
                    continuation.yield(.completed(UsageStats(inputTokens: inputTokens, outputTokens: outputTokens)))
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
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

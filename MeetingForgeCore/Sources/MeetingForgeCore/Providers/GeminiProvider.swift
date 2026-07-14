import Foundation

public struct GeminiProvider: MinutesProvider {
    public let id: ProviderID = .gemini
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models/\(request.model):streamGenerateContent"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": request.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": request.userPrompt]]]],
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
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let content = candidates.first?["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]] {
                            for part in parts {
                                if let text = part["text"] as? String, !text.isEmpty {
                                    continuation.yield(.textDelta(text))
                                }
                            }
                        }
                        if let meta = json["usageMetadata"] as? [String: Any],
                           let input = meta["promptTokenCount"] as? Int {
                            usage = UsageStats(
                                inputTokens: input,
                                outputTokens: meta["candidatesTokenCount"] as? Int ?? 0)
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
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return models.compactMap { model in
            guard let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent"),
                  let name = model["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
    }
}

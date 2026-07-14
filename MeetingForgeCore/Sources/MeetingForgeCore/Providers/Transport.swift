import Foundation

public protocol StreamTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
}

public struct URLSessionTransport: StreamTransport {
    public init() {}

    public func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("non-HTTP response")
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
    }
}

public enum SSEParser {
    public static func payload(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return payload
    }
}

/// Shared helper: read an error body from a line stream and throw ProviderError.http.
func throwHTTPError(status: Int, lines: AsyncThrowingStream<String, Error>) async throws -> Never {
    var body = ""
    for try await line in lines { body += line; if body.count > 4000 { break } }
    throw ProviderError.http(status: status, message: body)
}

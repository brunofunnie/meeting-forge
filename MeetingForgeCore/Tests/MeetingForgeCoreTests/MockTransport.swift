import Foundation
@testable import MeetingForgeCore

struct MockTransport: StreamTransport {
    var status: Int = 200
    var bodyLines: [String]
    /// Captures the last request for assertions.
    let captured = CapturedRequest()

    final class CapturedRequest: @unchecked Sendable {
        var request: URLRequest?
    }

    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        captured.request = request
        let http = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        let lines = bodyLines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
        return (http, stream)
    }
}

/// Drains a provider stream into (text, usage) for test assertions.
func drain(_ stream: AsyncThrowingStream<MinutesEvent, Error>) async throws -> (String, UsageStats?) {
    var text = ""
    var usage: UsageStats?
    for try await event in stream {
        switch event {
        case .textDelta(let delta): text += delta
        case .completed(let stats): usage = stats
        }
    }
    return (text, usage)
}

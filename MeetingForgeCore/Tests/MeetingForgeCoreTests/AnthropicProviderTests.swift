import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "claude-sonnet-4-5", apiKey: "ak-test")

@Test func anthropicStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        "event: message_start",
        "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":200,\"output_tokens\":1}}}",
        "event: content_block_delta",
        "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"# Minutes\"}}",
        "event: content_block_delta",
        "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\" done\"}}",
        "event: message_delta",
        "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":77}}",
        "event: message_stop",
        "data: {\"type\":\"message_stop\"}",
    ])
    let provider = AnthropicProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Minutes done")
    #expect(usage == UsageStats(inputTokens: 200, outputTokens: 77))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(req.value(forHTTPHeaderField: "x-api-key") == "ak-test")
    #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(body["system"] as? String == "sys")
    #expect(body["max_tokens"] as? Int == 8192)
}

@Test func anthropicListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        "{\"data\":[{\"id\":\"claude-sonnet-4-5\"},{\"id\":\"claude-haiku-4-5\"}]}"
    ])
    let provider = AnthropicProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "ak-test")
    #expect(models == ["claude-sonnet-4-5", "claude-haiku-4-5"])
}

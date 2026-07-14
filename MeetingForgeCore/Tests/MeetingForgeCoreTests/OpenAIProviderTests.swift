import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript here", model: "gpt-5.2", apiKey: "sk-test")

@Test func openAIStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        "data: {\"choices\":[{\"delta\":{\"content\":\"# Ata\"}}]}",
        "data: {\"choices\":[{\"delta\":{\"content\":\" de reunião\"}}]}",
        "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":120,\"completion_tokens\":45}}",
        "data: [DONE]",
    ])
    let provider = OpenAIProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata de reunião")
    #expect(usage == UsageStats(inputTokens: 120, outputTokens: 45))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(body["model"] as? String == "gpt-5.2")
    #expect(body["stream"] as? Bool == true)
    #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
}

@Test func openAIMissingKeyThrows() async {
    let provider = OpenAIProvider(transport: MockTransport(bodyLines: []))
    var req = request; req.apiKey = nil
    await #expect(throws: ProviderError.self) { _ = try await provider.generate(req) }
}

@Test func openAIHTTPErrorSurfacesBody() async throws {
    let transport = MockTransport(status: 429, bodyLines: ["{\"error\":{\"message\":\"rate limited\"}}"])
    let provider = OpenAIProvider(transport: transport)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func openAIListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        "{\"data\":[{\"id\":\"gpt-5.2\"},{\"id\":\"gpt-5-mini\"},{\"id\":\"whisper-1\"}]}"
    ])
    let provider = OpenAIProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "sk-test")
    #expect(models.contains("gpt-5.2"))
    #expect(transport.captured.request?.url?.absoluteString == "https://api.openai.com/v1/models")
}

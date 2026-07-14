import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "gpt-oss:120b", apiKey: "ol-test")

@Test func ollamaStreamsJSONLines() async throws {
    let transport = MockTransport(bodyLines: [
        "{\"message\":{\"role\":\"assistant\",\"content\":\"# Minutes\"},\"done\":false}",
        "{\"message\":{\"role\":\"assistant\",\"content\":\" end\"},\"done\":false}",
        "{\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"done\":true,\"prompt_eval_count\":500,\"eval_count\":150}",
    ])
    let provider = OllamaCloudProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Minutes end")
    #expect(usage == UsageStats(inputTokens: 500, outputTokens: 150))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://ollama.com/api/chat")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer ol-test")
}

@Test func ollamaListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        "{\"models\":[{\"name\":\"gpt-oss:120b\"},{\"name\":\"deepseek-v3.1:671b\"}]}"
    ])
    let provider = OllamaCloudProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "ol-test")
    #expect(models == ["gpt-oss:120b", "deepseek-v3.1:671b"])
    #expect(transport.captured.request?.url?.absoluteString == "https://ollama.com/api/tags")
}

@Test func localOllamaWorksWithoutAPIKey() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"message":{"role":"assistant","content":"local minutes"},"done":false}"#,
        #"{"message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":10,"eval_count":5}"#,
    ])
    let provider = OllamaCloudProvider(
        id: .ollamaLocal, transport: transport,
        baseURL: URL(string: "http://localhost:11434")!, requiresAuth: false)
    let keylessRequest = MinutesRequest(
        systemPrompt: "sys", userPrompt: "transcript", model: "llama3.2", apiKey: nil)
    let (text, usage) = try await drain(try await provider.generate(keylessRequest))
    #expect(text == "local minutes")
    #expect(usage == UsageStats(inputTokens: 10, outputTokens: 5))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "http://localhost:11434/api/chat")
    #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func localOllamaListsModelsWithoutKey() async throws {
    let transport = MockTransport(bodyLines: [#"{"models":[{"name":"llama3.2"}]}"#])
    let provider = OllamaCloudProvider(
        id: .ollamaLocal, transport: transport,
        baseURL: URL(string: "http://localhost:11434")!, requiresAuth: false)
    let models = try await provider.listModels(apiKey: nil)
    #expect(models == ["llama3.2"])
    #expect(transport.captured.request?.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func cloudOllamaStillRequiresKey() async {
    let provider = OllamaCloudProvider(transport: MockTransport(bodyLines: []))
    var keyless = request; keyless.apiKey = nil
    await #expect(throws: ProviderError.self) { _ = try await provider.generate(keyless) }
}

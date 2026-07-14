import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "gemini-2.5-pro", apiKey: "g-test")

@Test func geminiStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"# Ata\"}]}}]}",
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" final\"}]}}],\"usageMetadata\":{\"promptTokenCount\":300,\"candidatesTokenCount\":90}}",
    ])
    let provider = GeminiProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata final")
    #expect(usage == UsageStats(inputTokens: 300, outputTokens: 90))

    let req = transport.captured.request!
    #expect(req.url!.absoluteString.contains("models/gemini-2.5-pro:streamGenerateContent"))
    #expect(req.url!.absoluteString.contains("alt=sse"))
    #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-test")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    let sys = body["systemInstruction"] as! [String: Any]
    #expect(((sys["parts"] as! [[String: Any]])[0]["text"] as! String) == "sys")
}

@Test func geminiListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        "{\"models\":[{\"name\":\"models/gemini-2.5-pro\",\"supportedGenerationMethods\":[\"generateContent\"]},{\"name\":\"models/embedding-001\",\"supportedGenerationMethods\":[\"embedContent\"]}]}"
    ])
    let provider = GeminiProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "g-test")
    #expect(models == ["gemini-2.5-pro"]) // strips "models/" prefix, filters non-generateContent
}

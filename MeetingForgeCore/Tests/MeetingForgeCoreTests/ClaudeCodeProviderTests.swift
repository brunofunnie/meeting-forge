import Testing
import Foundation
@testable import MeetingForgeCore

/// Writes an executable shell script that ignores stdin and prints canned JSON.
func makeStubCLI(json: String, exitCode: Int = 0) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-claude-stub-\(UUID().uuidString)")
    let script = """
    #!/bin/sh
    cat > /dev/null
    cat <<'EOF'
    \(json)
    EOF
    exit \(exitCode)
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private let request = MinutesRequest(
    systemPrompt: "You are a minute-taker.", userPrompt: "transcript", model: "sonnet")

@Test func parsesCLIResultAndUsage() async throws {
    let stub = try makeStubCLI(json: #"""
    {"type":"result","subtype":"success","is_error":false,"result":"# Ata\n\n- ponto 1","total_cost_usd":0.0042,"usage":{"input_tokens":900,"output_tokens":210}}
    """#)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata\n\n- ponto 1")
    #expect(usage?.inputTokens == 900)
    #expect(usage?.outputTokens == 210)
    #expect(usage?.reportedCostUSD == 0.0042)
}

@Test func cliErrorResultThrows() async throws {
    let stub = try makeStubCLI(json: #"{"type":"result","is_error":true,"result":"overloaded"}"#)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func nonZeroExitThrows() async throws {
    let stub = try makeStubCLI(json: "boom", exitCode: 3)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func missingExecutableThrows() async {
    let provider = ClaudeCodeProvider(executableURL: nil)
    await #expect(throws: ProviderError.self) { _ = try await provider.generate(request) }
}

@Test func staticModelList() async throws {
    let provider = ClaudeCodeProvider(executableURL: nil)
    let models = try await provider.listModels(apiKey: nil)
    #expect(models == ["sonnet", "opus", "haiku"])
}

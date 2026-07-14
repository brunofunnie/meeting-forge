import Foundation

public struct ClaudeCodeProvider: MinutesProvider {
    public let id: ProviderID = .claudeCode
    let executableURL: URL?

    public init(executableURL: URL?) {
        self.executableURL = executableURL
    }

    public static func detectExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to `which` through the user's login shell PATH.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let executableURL else {
            throw ProviderError.executableNotFound("claude CLI not found — install Claude Code or set the path in Settings")
        }
        let prompt = """
        \(request.systemPrompt)

        \(request.userPrompt)
        """
        let model = request.model

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = ["-p", "--output-format", "json", "--model", model]
                    let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
                    process.standardInput = stdinPipe
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(Data(prompt.utf8))
                    try stdinPipe.fileHandleForWriting.close()

                    let stdout = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
                    let stderr = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        throw ProviderError.cliFailure(
                            String(data: stderr, encoding: .utf8) ?? "exit \(process.terminationStatus)")
                    }
                    guard let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] else {
                        throw ProviderError.malformedResponse(
                            String(data: stdout, encoding: .utf8) ?? "empty stdout")
                    }
                    if json["is_error"] as? Bool == true {
                        throw ProviderError.cliFailure(json["result"] as? String ?? "unknown CLI error")
                    }
                    guard let result = json["result"] as? String else {
                        throw ProviderError.malformedResponse("missing result field")
                    }
                    let usageDict = json["usage"] as? [String: Any] ?? [:]
                    let usage = UsageStats(
                        inputTokens: usageDict["input_tokens"] as? Int ?? 0,
                        outputTokens: usageDict["output_tokens"] as? Int ?? 0,
                        reportedCostUSD: json["total_cost_usd"] as? Double)
                    continuation.yield(.textDelta(result))
                    continuation.yield(.completed(usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        ["sonnet", "opus", "haiku"]
    }
}

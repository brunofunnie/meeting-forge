import Testing
@testable import MeetingForgeCore

@Test func extractsDataPayload() {
    #expect(SSEParser.payload(fromLine: "data: {\"x\":1}") == "{\"x\":1}")
    #expect(SSEParser.payload(fromLine: "data:{\"x\":1}") == "{\"x\":1}")
}

@Test func skipsNoise() {
    #expect(SSEParser.payload(fromLine: "") == nil)
    #expect(SSEParser.payload(fromLine: ": keep-alive") == nil)
    #expect(SSEParser.payload(fromLine: "event: message_start") == nil)
    #expect(SSEParser.payload(fromLine: "data: [DONE]") == nil)
}

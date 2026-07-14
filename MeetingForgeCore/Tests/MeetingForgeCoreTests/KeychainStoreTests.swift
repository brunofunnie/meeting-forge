import Testing
import Foundation
@testable import MeetingForgeCore

@Test func setGetOverwriteDelete() throws {
    let store = KeychainStore(service: "com.funnietech.meetingforge.tests")
    let account = "test-\(UUID().uuidString)"
    defer { try? store.delete(account: account) }

    #expect(store.get(account: account) == nil)
    try store.set("secret-1", account: account)
    #expect(store.get(account: account) == "secret-1")
    try store.set("secret-2", account: account) // overwrite
    #expect(store.get(account: account) == "secret-2")
    try store.delete(account: account)
    #expect(store.get(account: account) == nil)
}

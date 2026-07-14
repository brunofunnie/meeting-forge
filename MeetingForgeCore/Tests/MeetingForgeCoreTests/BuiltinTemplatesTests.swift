import Testing
@testable import MeetingForgeCore

@Test func threeBuiltinsWithStableKeys() {
    let keys = BuiltinTemplates.all.map(\.key)
    #expect(keys == ["business", "it", "personal"])
    for template in BuiltinTemplates.all {
        #expect(!template.systemPrompt.isEmpty)
        #expect(!template.sections.isEmpty)
        #expect(BuiltinTemplates.template(forKey: template.key)?.name == template.name)
    }
}

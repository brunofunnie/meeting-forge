import SwiftUI
import SwiftData
import MeetingForgeCore

@main
struct MeetingForgeApp: App {
    let container: ModelContainer
    @State private var settings = SettingsStore()

    init() {
        do {
            container = try ModelContainer(
                for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self)
            Self.seedBuiltinTemplates(context: container.mainContext)
        } catch {
            fatalError("Cannot create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
        .modelContainer(container)
    }

    @MainActor
    static func seedBuiltinTemplates(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<MeetingTemplate>())) ?? []
        let existingKeys = Set(existing.compactMap(\.builtinKey))
        for builtin in BuiltinTemplates.all where !existingKeys.contains(builtin.key) {
            context.insert(MeetingTemplate(
                name: builtin.name, icon: builtin.icon,
                systemPrompt: builtin.systemPrompt, sections: builtin.sections,
                isBuiltin: true, builtinKey: builtin.key))
        }
        try? context.save()
    }
}

import SwiftUI
import SwiftData
import MeetingForgeCore

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]
    @State private var editing: MeetingTemplate?

    var body: some View {
        List {
            ForEach(templates) { template in
                HStack {
                    Label(template.name, systemImage: template.icon)
                    if template.isBuiltin {
                        Text("built-in").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editing = template }
                    if template.isBuiltin {
                        Button("Reset") { reset(template) }
                    } else {
                        Button(role: .destructive) {
                            context.delete(template)
                            try? context.save()
                        } label: { Text("Delete") }
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            Button {
                let template = MeetingTemplate(
                    name: "New Template", icon: "doc.text",
                    systemPrompt: "You are an expert minute-taker. Do not invent information.",
                    sections: ["Summary", "Action Points"])
                context.insert(template)
                try? context.save()
                editing = template
            } label: { Label("New Template", systemImage: "plus") }
        }
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template)
        }
    }

    private func reset(_ template: MeetingTemplate) {
        guard let key = template.builtinKey,
              let builtin = BuiltinTemplates.template(forKey: key) else { return }
        template.name = builtin.name
        template.icon = builtin.icon
        template.systemPrompt = builtin.systemPrompt
        template.sections = builtin.sections
        try? context.save()
    }
}

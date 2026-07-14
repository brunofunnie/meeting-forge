import SwiftUI
import SwiftData
import MeetingForgeCore

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: MeetingTemplate
    @State private var sectionsText = ""

    var body: some View {
        Form {
            TextField("Name", text: $template.name)
            TextField("SF Symbol icon", text: $template.icon)
            Section("System prompt") {
                TextEditor(text: $template.systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
            }
            Section("Sections (one per line, in order)") {
                TextEditor(text: $sectionsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
            }
            HStack {
                Spacer()
                Button("Done") {
                    template.sections = sectionsText
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
        .onAppear { sectionsText = template.sections.joined(separator: "\n") }
    }
}

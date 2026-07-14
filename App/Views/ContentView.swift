import SwiftUI
import SwiftData
import MeetingForgeCore

enum SidebarItem: Hashable {
    case newMeeting
    case history
    case templates
    case settings
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .newMeeting
    // Owned here (not in NewMeetingView) so form input and run progress
    // survive sidebar section switches, which recreate the detail view.
    @State private var newMeetingForm = NewMeetingFormModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("New Meeting", systemImage: "plus.circle").tag(SidebarItem.newMeeting)
                Label("History", systemImage: "clock").tag(SidebarItem.history)
                Label("Templates", systemImage: "doc.text").tag(SidebarItem.templates)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // Explicit stack, re-identified per section: a NavigationLink push
            // (History → MeetingDetailView) stays on the column's stack when the
            // sidebar selection changes, hiding the new root. Resetting identity
            // pops any pushed page when switching sections.
            NavigationStack {
                switch selection {
                case .newMeeting, nil: NewMeetingView(form: newMeetingForm)
                case .history: HistoryListView()
                case .templates: TemplateListView()
                case .settings: SettingsView()
                }
            }
            .id(selection)
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}

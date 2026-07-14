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
            switch selection {
            case .newMeeting, nil: NewMeetingView()
            case .history: HistoryListView()
            case .templates: TemplateListView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}

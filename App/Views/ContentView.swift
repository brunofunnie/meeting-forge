import SwiftUI
import MeetingForgeCore

struct ContentView: View {
    var body: some View {
        Text("MeetingForge \(MeetingForgeCoreInfo.version)")
            .frame(minWidth: 900, minHeight: 600)
    }
}

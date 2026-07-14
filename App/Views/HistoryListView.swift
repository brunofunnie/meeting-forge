import SwiftUI
import SwiftData
import MeetingForgeCore

struct HistoryListView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings yet",
                    systemImage: "clock",
                    description: Text("Process your first meeting from New Meeting."))
            } else {
                List {
                    ForEach(meetings) { meeting in
                        NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title).font(.headline)
                                HStack(spacing: 8) {
                                    Text(meeting.createdAt, style: .date)
                                    Text(statusLabel(meeting.status))
                                        .foregroundStyle(meeting.status == .failed ? .red : .secondary)
                                    if let run = meeting.minutesRuns.last {
                                        Text("\(run.provider.displayName) · \(run.modelName)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let meeting = meetings[index]
                            // NOTE: best-effort audio cleanup — Meeting has no stored UUID yet,
                            // so we approximate the folder name from the persistent model ID's
                            // hash. Known-imperfect; Task 18 fixes this once meetings carry a
                            // proper folder UUID via combinedAudioPath.
                            try? FileManager.default.removeItem(
                                at: AppPaths.root.appendingPathComponent("audio")
                                    .appendingPathComponent(meeting.persistentModelID.hashValue.description))
                            context.delete(meeting)
                        }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func statusLabel(_ status: MeetingStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .transcribing: "Transcribing…"
        case .generating: "Generating…"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

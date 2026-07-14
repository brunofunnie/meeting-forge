import SwiftUI
import SwiftData
import MeetingForgeCore

struct HistoryListView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Environment(\.modelContext) private var context
    @State private var meetingToDelete: Meeting?

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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title).font(.headline)
                                    HStack(spacing: 8) {
                                        Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        Text(statusLabel(meeting.status))
                                            .foregroundStyle(meeting.status == .failed ? .red : .secondary)
                                        if let run = meeting.minutesRuns.last {
                                            Text("\(run.provider.displayName) · \(run.modelName)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    meetingToDelete = meeting
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete meeting")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { delete(meetings[index]) }
                    }
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog(
            "Delete \"\(meetingToDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { meetingToDelete != nil },
                set: { if !$0 { meetingToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete { delete(meeting) }
                meetingToDelete = nil
            }
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
        } message: {
            Text("Removes the meeting, its transcript, minutes and audio files. This cannot be undone.")
        }
    }

    private func delete(_ meeting: Meeting) {
        if let uuid = meeting.audioFolderUUID {
            try? FileManager.default.removeItem(
                at: AppPaths.root.appendingPathComponent("audio")
                    .appendingPathComponent(uuid))
        }
        context.delete(meeting)
        try? context.save()
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

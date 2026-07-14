import SwiftUI
import MeetingForgeCore

struct RunProgressView: View {
    let viewModel: MeetingRunViewModel

    var body: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .running(let stage):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(label(stage))
                }
                if stage == .generating && !viewModel.liveMarkdown.isEmpty {
                    ScrollView {
                        Text(viewModel.liveMarkdown)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
        case .failed(let stage, let message):
            VStack(alignment: .leading, spacing: 4) {
                Label(stage.map { "Failed while \(label($0).lowercased())" } ?? "Failed",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message).font(.caption).textSelection(.enabled)
            }
        case .done:
            Label("Done — see History", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }

    private func label(_ stage: PipelineStage) -> String {
        switch stage {
        case .combining: "Combining audio…"
        case .transcribing: "Transcribing…"
        case .diarizing: "Identifying speakers…"
        case .generating: "Generating minutes…"
        }
    }
}

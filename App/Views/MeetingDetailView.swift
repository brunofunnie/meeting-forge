import SwiftUI
import SwiftData
import AVKit
import MeetingForgeCore

struct MeetingDetailView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]
    let meeting: Meeting

    @State private var tab = 0
    @State private var selectedRunIndex = 0
    @State private var runViewModel = MeetingRunViewModel()
    @State private var showRegenerate = false
    @State private var exportError: String?

    private var sortedRuns: [MinutesRun] {
        meeting.minutesRuns.sorted { $0.createdAt < $1.createdAt }
    }
    private var currentRun: MinutesRun? {
        sortedRuns.indices.contains(selectedRunIndex) ? sortedRuns[selectedRunIndex] : sortedRuns.last
    }

    var body: some View {
        TabView(selection: $tab) {
            minutesTab.tabItem { Text("Minutes") }.tag(0)
            transcriptTab.tabItem { Text("Transcript") }.tag(1)
            audioTab.tabItem { Text("Audio") }.tag(2)
            statsTab.tabItem { Text("Stats") }.tag(3)
        }
        .padding()
        .navigationTitle(meeting.title)
        .toolbar {
            ToolbarItemGroup {
                if let run = currentRun {
                    Menu("Export") {
                        Button("Markdown…") { saveFile(data: Data(run.markdown.utf8), ext: "md") }
                        Button("HTML…") {
                            saveFile(data: Data(MinutesExporter.html(
                                markdown: run.markdown, title: meeting.title).utf8), ext: "html")
                        }
                        Button("PDF…") { exportPDF(run: run) }
                        Divider()
                        Button("Copy as Markdown") {
                            MinutesExporter.copyToClipboard(markdown: run.markdown, richText: false)
                        }
                        Button("Copy as Rich Text") {
                            MinutesExporter.copyToClipboard(markdown: run.markdown, richText: true)
                        }
                    }
                }
                Button("Regenerate…") { showRegenerate = true }
                    .disabled(meeting.transcript == nil)
            }
        }
        .sheet(isPresented: $showRegenerate) {
            RegenerateSheet(meeting: meeting, templates: templates, runViewModel: runViewModel)
        }
        .alert("Export failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
        .onAppear { selectedRunIndex = max(0, sortedRuns.count - 1) }
    }

    private var minutesTab: some View {
        VStack(alignment: .leading) {
            if sortedRuns.count > 1 {
                Picker("Run", selection: $selectedRunIndex) {
                    ForEach(Array(sortedRuns.enumerated()), id: \.offset) { index, run in
                        Text("\(run.createdAt.formatted(date: .omitted, time: .shortened)) — \(run.provider.displayName)/\(run.modelName)")
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
            }
            if case .running = runViewModel.state {
                RunProgressView(viewModel: runViewModel)
            }
            ScrollView {
                if let run = currentRun,
                   let attributed = try? AttributedString(
                       markdown: run.markdown,
                       options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView("No minutes yet", systemImage: "doc.text")
                }
            }
        }
    }

    private var transcriptTab: some View {
        TranscriptTabView(meeting: meeting)
    }

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source files: \(meeting.sourceFileNames.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            if let path = meeting.combinedAudioPath {
                AudioPlayerView(url: URL(fileURLWithPath: path))
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            } else {
                ContentUnavailableView("No combined audio", systemImage: "waveform")
            }
            Spacer()
        }
    }

    private var statsTab: some View {
        Table(sortedRuns) {
            TableColumn("When") { Text($0.createdAt.formatted(date: .abbreviated, time: .shortened)) }
            TableColumn("Provider") { Text($0.provider.displayName) }
            TableColumn("Model") { Text($0.modelName) }
            TableColumn("Template") { Text($0.templateName) }
            TableColumn("In tokens") { Text("\($0.inputTokens)") }
            TableColumn("Out tokens") { Text("\($0.outputTokens)") }
            TableColumn("Total") { Text("\($0.totalTokens)") }
            TableColumn("Cost") { Text($0.costUSD, format: .currency(code: "USD").precision(.fractionLength(4))) }
            TableColumn("Latency") { Text("\($0.latencySeconds, specifier: "%.1f")s") }
        }
    }

    private func saveFile(data: Data, ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.title).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url) } catch { exportError = error.localizedDescription }
        }
    }

    private func exportPDF(run: MinutesRun) {
        Task {
            do {
                let data = try await MinutesExporter.pdf(markdown: run.markdown, title: meeting.title)
                saveFile(data: data, ext: "pdf")
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

struct TranscriptTabView: View {
    @Environment(\.modelContext) private var context
    let meeting: Meeting
    @State private var renames: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading) {
            if let transcript = meeting.transcript, let segments = try? transcript.segments() {
                if transcript.diarized {
                    let speakerIDs = Array(Set(segments.compactMap(\.speaker))).sorted()
                    HStack {
                        ForEach(speakerIDs, id: \.self) { id in
                            TextField(id, text: Binding(
                                get: { renames[id] ?? id },
                                set: { renames[id] = $0 }))
                                .frame(width: 120)
                        }
                        Button("Save names") {
                            try? transcript.setSpeakerNames(renames)
                            try? context.save()
                        }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            HStack(alignment: .top, spacing: 8) {
                                Text(PromptBuilder.timestamp(segment.start))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let speaker = segment.speaker {
                                    Text((renames[speaker] ?? speaker) + ":").bold()
                                }
                                Text(segment.text).textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No transcript", systemImage: "text.quote")
            }
        }
        .onAppear {
            renames = (try? meeting.transcript?.speakerNames()) ?? [:]
        }
    }
}

struct AudioPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 60)
            .onAppear { player = AVPlayer(url: url) }
            .onDisappear { player?.pause() }
    }
}

struct RegenerateSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: Meeting
    let templates: [MeetingTemplate]
    let runViewModel: MeetingRunViewModel

    @State private var provider: ProviderID = .anthropic
    @State private var model = ""
    @State private var templateName: String?

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField("Model", text: $model)
            Picker("Template", selection: $templateName) {
                ForEach(templates) { Text($0.name).tag(Optional($0.name)) }
            }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Regenerate") {
                    if let template = templates.first(where: { $0.name == templateName }) {
                        runViewModel.regenerate(
                            meeting: meeting, template: template, provider: provider,
                            model: model, settings: settings, context: context)
                        dismiss()
                    }
                }
                .disabled(model.isEmpty || templateName == nil)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            provider = settings.defaultProvider
            model = settings.defaultModel(for: provider) ?? ""
            templateName = templates.first?.name
        }
    }
}

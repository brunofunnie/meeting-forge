import SwiftUI
import SwiftData
import MeetingForgeCore
import UniformTypeIdentifiers

struct NewMeetingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @State private var title = ""
    @State private var files: [URL] = []
    @State private var language: MeetingLanguage = .auto
    @State private var diarize = false
    @State private var selectedTemplateName: String?
    @State private var provider: ProviderID = .anthropic
    @State private var model = ""
    @State private var availableModels: [String] = []
    @State private var showImporter = false
    @State private var runViewModel = MeetingRunViewModel()

    var body: some View {
        Form {
            Section("Meeting") {
                TextField("Title", text: $title, prompt: Text("e.g. Sprint Planning 14/07"))
                Picker("Language", selection: $language) {
                    ForEach(MeetingLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Speaker diarization", isOn: $diarize)
            }

            Section("Audio files (played in list order)") {
                List {
                    ForEach(files, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "waveform")
                    }
                    .onMove { from, to in files.move(fromOffsets: from, toOffset: to) }
                    .onDelete { files.remove(atOffsets: $0) }
                }
                .frame(minHeight: 80)
                Button("Add audio files…") { showImporter = true }
            }

            Section("Minutes") {
                Picker("Template", selection: $selectedTemplateName) {
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.name))
                    }
                }
                Picker("Provider", selection: $provider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Picker("Model", selection: $model) {
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        if !model.isEmpty && !availableModels.contains(model) {
                            Text(model).tag(model)
                        }
                    }
                    TextField("or custom model id", text: $model).frame(width: 200)
                    Button {
                        Task { await loadModels(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }

            Section {
                Button("Process meeting") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(files.isEmpty || model.isEmpty || selectedTemplateName == nil
                              || (runViewModel.state != .idle && runViewModel.state != .done))
                RunProgressView(viewModel: runViewModel)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Meeting")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files.append(contentsOf: urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for itemProvider in providers {
                _ = itemProvider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true {
                        Task { @MainActor in files.append(url) }
                    }
                }
            }
            return true
        }
        .task {
            provider = settings.defaultProvider
            selectedTemplateName = templates.first?.name
            await loadModels(force: false)
        }
        .onChange(of: provider) {
            model = settings.defaultModel(for: provider) ?? ""
            Task { await loadModels(force: false) }
        }
    }

    private func loadModels(force: Bool) async {
        let catalog = ModelCatalog()
        availableModels = (try? await catalog.models(
            for: settings.makeProvider(provider),
            apiKey: settings.apiKey(for: provider),
            forceRefresh: force)) ?? []
        if model.isEmpty { model = settings.defaultModel(for: provider) ?? availableModels.first ?? "" }
    }

    private func start() {
        guard let template = templates.first(where: { $0.name == selectedTemplateName }) else { return }
        settings.setDefaultModel(model, for: provider)
        let meetingTitle = title.isEmpty
            ? "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            : title
        runViewModel.start(
            title: meetingTitle, files: files, language: language, diarize: diarize,
            template: template, provider: provider, model: model,
            settings: settings, context: context)
    }
}

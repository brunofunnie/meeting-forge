import SwiftUI
import SwiftData
import MeetingForgeCore
import UniformTypeIdentifiers

/// Form state for New Meeting. Owned by ContentView so switching sidebar
/// sections (which recreates the detail view) doesn't lose user input or
/// a run already in progress.
@Observable @MainActor
final class NewMeetingFormModel {
    var title = ""
    var files: [URL] = []
    var language: MeetingLanguage = .auto
    var minutesLanguage: MinutesLanguage = .matchTranscript
    var diarize = false
    var selectedTemplateName: String?
    var provider: ProviderID = .anthropic
    var model = ""
    var availableModels: [String] = []
    var runViewModel = MeetingRunViewModel()
    var didLoadDefaults = false

    /// Clears every field back to defaults for a fresh meeting.
    @MainActor
    func reset(defaultProvider: ProviderID, defaultModel: String?, firstTemplateName: String?) {
        title = ""
        files = []
        language = .auto
        minutesLanguage = .matchTranscript
        diarize = false
        selectedTemplateName = firstTemplateName
        provider = defaultProvider
        model = defaultModel ?? ""
        runViewModel = MeetingRunViewModel()
    }
}

struct NewMeetingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @Bindable var form: NewMeetingFormModel
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("Meeting") {
                TextField("Title", text: $form.title, prompt: Text("e.g. Sprint Planning 14/07"))
                Picker("Language", selection: $form.language) {
                    ForEach(MeetingLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Minutes language", selection: $form.minutesLanguage) {
                    ForEach(MinutesLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Speaker diarization", isOn: $form.diarize)
            }

            Section("Audio files (played in list order)") {
                List {
                    ForEach(form.files, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "waveform")
                    }
                    .onMove { from, to in form.files.move(fromOffsets: from, toOffset: to) }
                    .onDelete { form.files.remove(atOffsets: $0) }
                }
                .frame(minHeight: 80)
                Button("Add audio files…") { showImporter = true }
            }

            Section("Minutes") {
                Picker("Template", selection: $form.selectedTemplateName) {
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.name))
                    }
                }
                Picker("Provider", selection: $form.provider) {
                    ForEach(ProviderID.allCases, id: \.self) { id in
                        if settings.isAvailable(id) {
                            Text(id.displayName).tag(id)
                        } else {
                            Text("\(id.displayName) — \(id == .claudeCode ? "CLI not found" : "no API key")")
                                .foregroundStyle(.secondary)
                                .tag(id)
                                .selectionDisabled()
                        }
                    }
                }
                HStack {
                    Picker("Model", selection: $form.model) {
                        ForEach(form.availableModels, id: \.self) { Text($0).tag($0) }
                        if !form.model.isEmpty && !form.availableModels.contains(form.model) {
                            Text(form.model).tag(form.model)
                        }
                    }
                    TextField("or custom model id", text: $form.model).frame(width: 200)
                    Button {
                        Task { await loadModels(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }

            Section {
                Button("Process meeting") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.files.isEmpty || form.model.isEmpty || form.selectedTemplateName == nil
                              || form.runViewModel.isRunning || !settings.isAvailable(form.provider))
                RunProgressView(viewModel: form.runViewModel)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Meeting")
        .toolbar {
            Button {
                form.reset(
                    defaultProvider: settings.defaultProvider,
                    defaultModel: settings.defaultModel(for: settings.defaultProvider),
                    firstTemplateName: templates.first?.name)
                Task { await loadModels(force: false) }
            } label: {
                Label("New Meeting", systemImage: "plus")
            }
            .help("Clear all fields and start a new meeting")
            .disabled(form.runViewModel.isRunning)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { form.files.append(contentsOf: urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for itemProvider in providers {
                _ = itemProvider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true {
                        Task { @MainActor in form.files.append(url) }
                    }
                }
            }
            return true
        }
        .task {
            // Only on first ever appearance — revisits keep the user's picks.
            guard !form.didLoadDefaults else { return }
            form.didLoadDefaults = true
            form.provider = settings.defaultProvider
            form.selectedTemplateName = templates.first?.name
            await loadModels(force: false)
        }
        .onChange(of: form.provider) {
            form.model = settings.defaultModel(for: form.provider) ?? ""
            Task { await loadModels(force: false) }
        }
    }

    private func loadModels(force: Bool) async {
        let catalog = ModelCatalog()
        form.availableModels = (try? await catalog.models(
            for: settings.makeProvider(form.provider),
            apiKey: settings.apiKey(for: form.provider),
            forceRefresh: force)) ?? []
        if form.model.isEmpty {
            form.model = settings.defaultModel(for: form.provider) ?? form.availableModels.first ?? ""
        }
    }

    private func start() {
        guard let template = templates.first(where: { $0.name == form.selectedTemplateName }) else { return }
        settings.setDefaultModel(form.model, for: form.provider)
        let meetingTitle = form.title.isEmpty
            ? "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            : form.title
        form.runViewModel.start(
            title: meetingTitle, files: form.files, language: form.language, diarize: form.diarize,
            minutesLanguage: form.minutesLanguage,
            template: template, provider: form.provider, model: form.model,
            settings: settings, context: context)
    }
}

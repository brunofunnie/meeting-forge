import SwiftUI
import MeetingForgeCore

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var keys: [ProviderID: String] = [:]
    @State private var claudeStatus: String = ""
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadedModels: [String] = []
    @State private var downloadError: String?

    private var whisperManager: WhisperKitModelManager {
        WhisperKitModelManager(modelsDirectory: AppPaths.whisperModelsDirectory)
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Transcription") {
                Picker("Engine", selection: $settings.engineID) {
                    ForEach(TranscriptionEngineID.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                if settings.engineID == .whisperKit {
                    Picker("Whisper model", selection: $settings.whisperModel) {
                        ForEach(WhisperKitModelManager.recommendedModels, id: \.self) { model in
                            Text(model + (downloadedModels.contains(model) ? " ✓" : "")).tag(model)
                        }
                    }
                    ForEach(WhisperKitModelManager.recommendedModels, id: \.self) { model in
                        HStack {
                            Text(model).font(.caption)
                            Spacer()
                            if let progress = downloadProgress[model] {
                                ProgressView(value: progress).frame(width: 120)
                            } else if downloadedModels.contains(model) {
                                Button("Delete") {
                                    try? whisperManager.delete(model)
                                    refreshModels()
                                }
                            } else {
                                Button("Download") { download(model) }
                            }
                        }
                    }
                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("AI Providers — API Keys") {
                ForEach(ProviderID.allCases.filter(\.requiresAPIKey), id: \.self) { provider in
                    SecureField(provider.displayName, text: binding(for: provider))
                        .onSubmit { persist(provider) }
                }
                Picker("Default provider", selection: $settings.defaultProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("Ollama (local)") {
                TextField("Server URL", text: $settings.ollamaLocalURL,
                          prompt: Text(SettingsStore.defaultOllamaLocalURL))
                SecureField("API key (optional)", text: binding(for: .ollamaLocal))
                    .onSubmit { persist(.ollamaLocal) }
                Text("Key is only sent when set — a stock local install needs none.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude Code") {
                TextField("Executable path (empty = auto-detect)",
                          text: Binding(
                            get: { settings.claudeExecutablePath ?? "" },
                            set: { settings.claudeExecutablePath = $0.isEmpty ? nil : $0 }))
                HStack {
                    Button("Check") {
                        claudeStatus = settings.claudeExecutableURL().map { "Found: \($0.path)" }
                            ?? "claude CLI not found — install Claude Code first"
                    }
                    Text(claudeStatus).font(.caption).foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            refreshModels()
            for provider in keyedProviders {
                keys[provider] = settings.apiKey(for: provider) ?? ""
            }
        }
        .onDisappear {
            for provider in keyedProviders {
                persist(provider)
            }
        }
    }

    /// Providers whose key lives in the local `keys` buffer: the mandatory-key
    /// ones plus Ollama local, whose key is optional.
    private var keyedProviders: [ProviderID] {
        ProviderID.allCases.filter { $0.requiresAPIKey || $0 == .ollamaLocal }
    }

    private func binding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { newValue in
                keys[provider] = newValue
            })
    }

    private func persist(_ provider: ProviderID) {
        settings.setAPIKey(keys[provider] ?? "", for: provider)
    }

    private func refreshModels() {
        downloadedModels = whisperManager.downloadedModels()
    }

    private func download(_ model: String) {
        downloadProgress[model] = 0
        downloadError = nil
        Task {
            do {
                let manager = whisperManager
                try await manager.download(model) { fraction in
                    Task { @MainActor in downloadProgress[model] = fraction }
                }
            } catch {
                downloadError = "Download failed: \(error.localizedDescription)"
            }
            downloadProgress[model] = nil
            refreshModels()
        }
    }
}

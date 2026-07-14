# MeetingForge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS app that combines audio files, transcribes locally (optional diarization), generates meeting minutes via a chosen AI provider/model, exports MD/HTML/PDF/clipboard, and keeps history with token/cost stats.

**Architecture:** Two-layer split — `MeetingForgeCore` local Swift Package holds all compute logic (audio, transcription engines, diarization, providers, pipeline, export) and is fully testable with `swift test`; a thin SwiftUI app target (generated with XcodeGen) owns persistence wiring (SwiftData) and views. Engines and providers sit behind protocols (`TranscriptionEngine`, `MinutesProvider`) so both transcription backends and all five AI providers are swappable.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData (macOS 26), AVFoundation, Speech (SpeechAnalyzer), WhisperKit (SPM), FluidAudio (SPM), Ink (Markdown→HTML), WebKit (PDF), XcodeGen, Swift Testing (`@Test`).

## Global Constraints

- Deployment target: **macOS 26.0**. Swift tools version **6.2**. Xcode 26.
- App is **not sandboxed** (direct distribution; Claude Code CLI subprocess and Ollama-style local tooling need it). Hardened runtime OK.
- Languages supported: **pt-BR** and **en**; minutes output language = transcript language.
- Bundle ID: `com.funnietech.meetingforge`. App name: **MeetingForge**.
- Files live under `~/Library/Application Support/MeetingForge/`. API keys **only** in Keychain (service `com.funnietech.meetingforge`).
- SPM dependencies: WhisperKit, FluidAudio, Ink — pin `from:` latest release at implementation time.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`) in `MeetingForgeCore/Tests`.
- Run package tests with: `swift test --package-path MeetingForgeCore`
- Regenerate Xcode project after project.yml changes: `xcodegen generate`
- Every commit message ends with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Network calls in Core go through the `StreamTransport` / `JSONTransport` protocols so tests never hit the network.

## File Structure

```
meetingforge/
├── project.yml                          # XcodeGen manifest (app target)
├── MeetingForge.xcodeproj               # generated — never hand-edit
├── App/
│   ├── MeetingForgeApp.swift            # @main, ModelContainer, seeding
│   ├── AppPaths.swift                   # Application Support dirs
│   ├── ViewModels/
│   │   ├── MeetingRunViewModel.swift    # pipeline → SwiftData bridge
│   │   └── SettingsStore.swift          # defaults, engine choice, prices
│   └── Views/
│       ├── ContentView.swift            # NavigationSplitView shell
│       ├── HistoryListView.swift
│       ├── NewMeetingView.swift
│       ├── RunProgressView.swift
│       ├── MeetingDetailView.swift      # tabs: Minutes|Transcript|Audio|Stats
│       ├── TemplateListView.swift
│       ├── TemplateEditorView.swift
│       └── SettingsView.swift
├── MeetingForgeCore/
│   ├── Package.swift
│   ├── Sources/MeetingForgeCore/
│   │   ├── Models/CoreTypes.swift       # value types + enums
│   │   ├── Models/PersistentModels.swift# SwiftData @Model classes
│   │   ├── Audio/AudioCombiner.swift
│   │   ├── Transcription/TranscriptionEngine.swift   # protocol
│   │   ├── Transcription/AppleSpeechEngine.swift
│   │   ├── Transcription/WhisperKitEngine.swift
│   │   ├── Diarization/SpeakerMerger.swift
│   │   ├── Diarization/DiarizationService.swift      # FluidAudio wrapper
│   │   ├── Providers/MinutesProvider.swift           # protocol + events
│   │   ├── Providers/PromptBuilder.swift
│   │   ├── Providers/Transport.swift                 # StreamTransport, SSE
│   │   ├── Providers/OpenAIProvider.swift
│   │   ├── Providers/AnthropicProvider.swift
│   │   ├── Providers/GeminiProvider.swift
│   │   ├── Providers/OllamaCloudProvider.swift
│   │   ├── Providers/ClaudeCodeProvider.swift
│   │   ├── Providers/ModelCatalog.swift
│   │   ├── Providers/CostCalculator.swift
│   │   ├── Security/KeychainStore.swift
│   │   ├── Pipeline/PipelineCoordinator.swift
│   │   ├── Export/MinutesExporter.swift              # MD/HTML/PDF/clipboard
│   │   └── Templates/BuiltinTemplates.swift
│   └── Tests/MeetingForgeCoreTests/
│       ├── CoreTypesTests.swift
│       ├── PersistentModelsTests.swift
│       ├── AudioCombinerTests.swift
│       ├── SpeakerMergerTests.swift
│       ├── PromptBuilderTests.swift
│       ├── SSEParserTests.swift
│       ├── OpenAIProviderTests.swift
│       ├── AnthropicProviderTests.swift
│       ├── GeminiProviderTests.swift
│       ├── OllamaCloudProviderTests.swift
│       ├── ClaudeCodeProviderTests.swift
│       ├── ModelCatalogTests.swift
│       ├── CostCalculatorTests.swift
│       ├── KeychainStoreTests.swift
│       ├── PipelineCoordinatorTests.swift
│       ├── MinutesExporterTests.swift
│       └── BuiltinTemplatesTests.swift
└── docs/superpowers/...                 # specs + this plan
```

---

### Task 1: Scaffold — Swift Package + XcodeGen app shell

**Files:**
- Create: `MeetingForgeCore/Package.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Models/CoreTypes.swift` (placeholder marker type only, replaced in Task 2)
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/CoreTypesTests.swift`
- Create: `project.yml`
- Create: `App/MeetingForgeApp.swift`
- Create: `App/Views/ContentView.swift` (minimal, replaced in Task 17)
- Create: `.gitignore`

**Interfaces:**
- Produces: buildable package `MeetingForgeCore` (import name `MeetingForgeCore`) and app target `MeetingForge`; all later tasks add sources to these.

- [ ] **Step 1: Verify toolchain**

Run: `xcodebuild -version && swift --version && (which xcodegen || brew install xcodegen)`
Expected: Xcode 26.x, Swift 6.2+, xcodegen path.

- [ ] **Step 2: Write Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingForgeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MeetingForgeCore", targets: ["MeetingForgeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "MeetingForgeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Ink", package: "Ink"),
            ]
        ),
        .testTarget(name: "MeetingForgeCoreTests", dependencies: ["MeetingForgeCore"]),
    ]
)
```

Note: if a `from:` version fails to resolve, check the repo's latest release tag and adjust — do not switch to `branch: "main"`.

- [ ] **Step 3: Write seed source + failing test**

`MeetingForgeCore/Sources/MeetingForgeCore/Models/CoreTypes.swift`:

```swift
public enum MeetingForgeCoreInfo {
    public static let version = "0.1.0"
}
```

`MeetingForgeCore/Tests/MeetingForgeCoreTests/CoreTypesTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func packageBuilds() {
    #expect(MeetingForgeCoreInfo.version == "0.1.0")
}
```

- [ ] **Step 4: Run package tests**

Run: `swift test --package-path MeetingForgeCore`
Expected: 1 test passes (first run resolves SPM deps — slow).

- [ ] **Step 5: Write project.yml**

```yaml
name: MeetingForge
options:
  bundleIdPrefix: com.funnietech
  deploymentTarget:
    macOS: "26.0"
packages:
  MeetingForgeCore:
    path: MeetingForgeCore
targets:
  MeetingForge:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - package: MeetingForgeCore
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: MeetingForge
        NSSpeechRecognitionUsageDescription: "MeetingForge transcribes your meeting audio on-device."
        LSMinimumSystemVersion: "26.0"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.funnietech.meetingforge
        ENABLE_APP_SANDBOX: NO
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "6.0"
```

- [ ] **Step 6: Write minimal app**

`App/MeetingForgeApp.swift`:

```swift
import SwiftUI

@main
struct MeetingForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`App/Views/ContentView.swift`:

```swift
import SwiftUI
import MeetingForgeCore

struct ContentView: View {
    var body: some View {
        Text("MeetingForge \(MeetingForgeCoreInfo.version)")
            .frame(minWidth: 900, minHeight: 600)
    }
}
```

`.gitignore`:

```
.DS_Store
*.xcodeproj
.build/
DerivedData/
```

- [ ] **Step 7: Generate + build app**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: scaffold MeetingForgeCore package and app shell"
```

---

### Task 2: Core value types + SwiftData models

**Files:**
- Modify: `MeetingForgeCore/Sources/MeetingForgeCore/Models/CoreTypes.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Models/PersistentModels.swift`
- Modify: `MeetingForgeCore/Tests/MeetingForgeCoreTests/CoreTypesTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/PersistentModelsTests.swift`

**Interfaces:**
- Produces (used by all later tasks):
  - `MeetingLanguage` (`.portugueseBR/.english/.auto`, `rawValue` "pt-BR"/"en"/"auto", `var localeIdentifier: String?`)
  - `TranscriptSegment { start: TimeInterval, end: TimeInterval, text: String, speaker: String? }`
  - `SpeakerTurn { start: TimeInterval, end: TimeInterval, speakerID: String }`
  - `UsageStats { inputTokens: Int, outputTokens: Int, reportedCostUSD: Double?, totalTokens: Int }`
  - `ProviderID` enum: `.openAI/.anthropic/.gemini/.ollamaCloud/.claudeCode` with `displayName: String`
  - `TranscriptionEngineID` enum: `.appleSpeech/.whisperKit`
  - `MeetingStatus` enum: `.pending/.transcribing/.generating/.done/.failed`
  - SwiftData `@Model` classes: `Meeting`, `Transcript`, `MinutesRun`, `MeetingTemplate` (properties below)

- [ ] **Step 1: Write failing tests**

Replace `CoreTypesTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

@Test func languageLocales() {
    #expect(MeetingLanguage.portugueseBR.localeIdentifier == "pt_BR")
    #expect(MeetingLanguage.english.localeIdentifier == "en_US")
    #expect(MeetingLanguage.auto.localeIdentifier == nil)
    #expect(MeetingLanguage(rawValue: "pt-BR") == .portugueseBR)
}

@Test func usageStatsTotals() {
    let u = UsageStats(inputTokens: 1200, outputTokens: 300, reportedCostUSD: nil)
    #expect(u.totalTokens == 1500)
}

@Test func segmentRoundTripsJSON() throws {
    let seg = TranscriptSegment(start: 0.5, end: 2.0, text: "hello", speaker: "S1")
    let data = try JSONEncoder().encode([seg])
    let back = try JSONDecoder().decode([TranscriptSegment].self, from: data)
    #expect(back == [seg])
}

@Test func providerDisplayNames() {
    #expect(ProviderID.openAI.displayName == "OpenAI")
    #expect(ProviderID.claudeCode.displayName == "Claude Code")
    #expect(ProviderID.allCases.count == 5)
}
```

Create `PersistentModelsTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import MeetingForgeCore

@MainActor
@Test func meetingGraphPersists() throws {
    let container = try ModelContainer(
        for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let meeting = Meeting(title: "Sprint Planning", language: .portugueseBR)
    meeting.sourceFileNames = ["a.m4a", "b.m4a"]
    let transcript = Transcript(engine: .appleSpeech, diarized: true)
    try transcript.setSegments([TranscriptSegment(start: 0, end: 1, text: "olá", speaker: "S1")])
    meeting.transcript = transcript
    let run = MinutesRun(provider: .anthropic, modelName: "claude-sonnet-4-5",
                         templateName: "Business", markdown: "# Ata",
                         inputTokens: 100, outputTokens: 50, costUSD: 0.01, latencySeconds: 3.2)
    meeting.minutesRuns.append(run)
    ctx.insert(meeting)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Meeting>())
    #expect(fetched.count == 1)
    #expect(fetched[0].status == .pending)
    #expect(try fetched[0].transcript?.segments().first?.text == "olá")
    #expect(fetched[0].minutesRuns.first?.totalTokens == 150)
}

@MainActor
@Test func speakerRenamesPersist() throws {
    let container = try ModelContainer(
        for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let transcript = Transcript(engine: .whisperKit, diarized: true)
    try transcript.setSpeakerNames(["S1": "Bruno", "S2": "Ana"])
    container.mainContext.insert(transcript)
    #expect(try transcript.speakerNames()["S1"] == "Bruno")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --package-path MeetingForgeCore`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement CoreTypes.swift**

Replace file contents:

```swift
import Foundation

public enum MeetingForgeCoreInfo {
    public static let version = "0.1.0"
}

public enum MeetingLanguage: String, Codable, CaseIterable, Sendable {
    case portugueseBR = "pt-BR"
    case english = "en"
    case auto = "auto"

    /// Locale for speech APIs; nil means detect automatically.
    public var localeIdentifier: String? {
        switch self {
        case .portugueseBR: "pt_BR"
        case .english: "en_US"
        case .auto: nil
        }
    }

    public var displayName: String {
        switch self {
        case .portugueseBR: "Português (BR)"
        case .english: "English"
        case .auto: "Auto-detect"
        }
    }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: String?

    public init(start: TimeInterval, end: TimeInterval, text: String, speaker: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct SpeakerTurn: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speakerID: String

    public init(start: TimeInterval, end: TimeInterval, speakerID: String) {
        self.start = start
        self.end = end
        self.speakerID = speakerID
    }
}

public struct UsageStats: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Set only when the provider reports cost itself (Claude Code CLI).
    public var reportedCostUSD: Double?

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int, reportedCostUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reportedCostUSD = reportedCostUSD
    }
}

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case ollamaCloud = "ollama-cloud"
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic (Claude API)"
        case .gemini: "Google AI Studio (Gemini)"
        case .ollamaCloud: "Ollama Cloud"
        case .claudeCode: "Claude Code"
        }
    }

    /// Providers that need an API key stored in Keychain.
    public var requiresAPIKey: Bool { self != .claudeCode }
}

public enum TranscriptionEngineID: String, Codable, CaseIterable, Sendable {
    case appleSpeech = "apple-speech"
    case whisperKit = "whisperkit"

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech (built-in)"
        case .whisperKit: "WhisperKit (Whisper models)"
        }
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case pending, transcribing, generating, done, failed
}
```

`ProviderID.displayName` for `.openAI` must be exactly `"OpenAI"` and `.claudeCode` exactly `"Claude Code"` (tests assert).

- [ ] **Step 4: Implement PersistentModels.swift**

```swift
import Foundation
import SwiftData

@Model
public final class Meeting {
    public var title: String
    public var createdAt: Date
    public var sourceFileNames: [String]
    public var combinedAudioPath: String?
    public var durationSeconds: Double
    public var languageRaw: String
    public var statusRaw: String

    @Relationship(deleteRule: .cascade) public var transcript: Transcript?
    @Relationship(deleteRule: .cascade) public var minutesRuns: [MinutesRun]

    public var language: MeetingLanguage {
        get { MeetingLanguage(rawValue: languageRaw) ?? .auto }
        set { languageRaw = newValue.rawValue }
    }

    public var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(title: String, language: MeetingLanguage, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
        self.sourceFileNames = []
        self.combinedAudioPath = nil
        self.durationSeconds = 0
        self.languageRaw = language.rawValue
        self.statusRaw = MeetingStatus.pending.rawValue
        self.minutesRuns = []
    }
}

@Model
public final class Transcript {
    public var text: String
    public var segmentsData: Data
    public var engineRaw: String
    public var diarized: Bool
    public var wallTimeSeconds: Double
    public var speakerNamesData: Data

    public var engine: TranscriptionEngineID {
        get { TranscriptionEngineID(rawValue: engineRaw) ?? .appleSpeech }
        set { engineRaw = newValue.rawValue }
    }

    public init(engine: TranscriptionEngineID, diarized: Bool) {
        self.text = ""
        self.segmentsData = Data("[]".utf8)
        self.engineRaw = engine.rawValue
        self.diarized = diarized
        self.wallTimeSeconds = 0
        self.speakerNamesData = Data("{}".utf8)
    }

    public func segments() throws -> [TranscriptSegment] {
        try JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)
    }

    public func setSegments(_ segments: [TranscriptSegment]) throws {
        segmentsData = try JSONEncoder().encode(segments)
        text = segments.map(\.text).joined(separator: " ")
    }

    public func speakerNames() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: speakerNamesData)
    }

    public func setSpeakerNames(_ names: [String: String]) throws {
        speakerNamesData = try JSONEncoder().encode(names)
    }
}

@Model
public final class MinutesRun {
    public var createdAt: Date
    public var markdown: String
    public var providerRaw: String
    public var modelName: String
    public var templateName: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double
    public var latencySeconds: Double

    public var provider: ProviderID {
        get { ProviderID(rawValue: providerRaw) ?? .openAI }
        set { providerRaw = newValue.rawValue }
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(provider: ProviderID, modelName: String, templateName: String,
                markdown: String, inputTokens: Int, outputTokens: Int,
                costUSD: Double, latencySeconds: Double, createdAt: Date = .now) {
        self.createdAt = createdAt
        self.markdown = markdown
        self.providerRaw = provider.rawValue
        self.modelName = modelName
        self.templateName = templateName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.latencySeconds = latencySeconds
    }
}

@Model
public final class MeetingTemplate {
    public var name: String
    public var icon: String
    public var systemPrompt: String
    public var sections: [String]
    public var isBuiltin: Bool
    /// Stable key for builtins so "reset to default" can find the original.
    public var builtinKey: String?

    public init(name: String, icon: String, systemPrompt: String,
                sections: [String], isBuiltin: Bool = false, builtinKey: String? = nil) {
        self.name = name
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.sections = sections
        self.isBuiltin = isBuiltin
        self.builtinKey = builtinKey
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --package-path MeetingForgeCore`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: core value types and SwiftData models"
```

---

### Task 3: AudioCombiner

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Audio/AudioCombiner.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/AudioCombinerTests.swift`

**Interfaces:**
- Produces: `AudioCombiner.combine(fileURLs: [URL], outputURL: URL) async throws -> TimeInterval` (returns total duration in seconds; single input file is still exported to `outputURL` so downstream always reads one m4a). `AudioCombinerError` enum: `.noInput`, `.undecodable(URL)`, `.exportFailed(String)`.

- [ ] **Step 1: Write failing test with generated WAV fixtures**

`AudioCombinerTests.swift`:

```swift
import Testing
import Foundation
import AVFoundation
@testable import MeetingForgeCore

/// Writes a mono 16kHz sine-wave WAV of the given duration and returns its URL.
func makeWavFixture(seconds: Double, frequency: Double = 440, name: String) throws -> URL {
    let sampleRate = 16_000.0
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-fixture-\(name)-\(UUID().uuidString).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        data[i] = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate)) * 0.5
    }
    try file.write(from: buffer)
    return url
}

@Test func combinesTwoFilesInOrder() async throws {
    let a = try makeWavFixture(seconds: 2.0, name: "a")
    let b = try makeWavFixture(seconds: 3.0, name: "b")
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-combined-\(UUID().uuidString).m4a")

    let duration = try await AudioCombiner.combine(fileURLs: [a, b], outputURL: out)

    #expect(abs(duration - 5.0) < 0.2)
    let asset = AVURLAsset(url: out)
    let assetDuration = try await asset.load(.duration).seconds
    #expect(abs(assetDuration - 5.0) < 0.2)
}

@Test func singleFileStillExports() async throws {
    let a = try makeWavFixture(seconds: 1.5, name: "solo")
    let out = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-single-\(UUID().uuidString).m4a")
    let duration = try await AudioCombiner.combine(fileURLs: [a], outputURL: out)
    #expect(abs(duration - 1.5) < 0.2)
    #expect(FileManager.default.fileExists(atPath: out.path))
}

@Test func emptyInputThrows() async {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("x.m4a")
    await #expect(throws: AudioCombinerError.noInput) {
        _ = try await AudioCombiner.combine(fileURLs: [], outputURL: out)
    }
}

@Test func undecodableFileThrows() async throws {
    let junk = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-junk-\(UUID().uuidString).mp3")
    try Data("not audio at all".utf8).write(to: junk)
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("y.m4a")
    await #expect(throws: AudioCombinerError.self) {
        _ = try await AudioCombiner.combine(fileURLs: [junk], outputURL: out)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter AudioCombiner`
Expected: FAIL — `AudioCombiner` not defined.

- [ ] **Step 3: Implement AudioCombiner.swift**

```swift
import Foundation
import AVFoundation

public enum AudioCombinerError: Error, Equatable {
    case noInput
    case undecodable(URL)
    case exportFailed(String)
}

public enum AudioCombiner {
    /// Concatenates the given audio files in order into a single AAC .m4a file.
    /// Returns the total duration in seconds.
    public static func combine(fileURLs: [URL], outputURL: URL) async throws -> TimeInterval {
        guard !fileURLs.isEmpty else { throw AudioCombinerError.noInput }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AudioCombinerError.exportFailed("cannot create composition track") }

        var cursor = CMTime.zero
        for url in fileURLs {
            let asset = AVURLAsset(url: url)
            let duration: CMTime
            let sourceTracks: [AVAssetTrack]
            do {
                duration = try await asset.load(.duration)
                sourceTracks = try await asset.loadTracks(withMediaType: .audio)
            } catch {
                throw AudioCombinerError.undecodable(url)
            }
            guard let sourceTrack = sourceTracks.first, duration.seconds > 0 else {
                throw AudioCombinerError.undecodable(url)
            }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, duration)
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCombinerError.exportFailed("cannot create export session")
        }
        do {
            try await export.export(to: outputURL, as: .m4a)
        } catch {
            throw AudioCombinerError.exportFailed(String(describing: error))
        }
        return cursor.seconds
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter AudioCombiner`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AudioCombiner concatenates audio files to m4a"
```

---

### Task 4: TranscriptionEngine protocol + SpeakerMerger

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Transcription/TranscriptionEngine.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Diarization/SpeakerMerger.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/SpeakerMergerTests.swift`

**Interfaces:**
- Produces:
  - `protocol TranscriptionEngine: Sendable { var id: TranscriptionEngineID { get }; func prepare(language: MeetingLanguage) async throws; func transcribe(fileURL: URL, language: MeetingLanguage, onProgress: @escaping @Sendable (Double?) -> Void) async throws -> [TranscriptSegment] }`
  - `TranscriptionError` enum: `.assetUnavailable(String)`, `.modelNotDownloaded(String)`, `.failed(String)`
  - `SpeakerMerger.merge(segments: [TranscriptSegment], turns: [SpeakerTurn]) -> [TranscriptSegment]`
- Consumes: `TranscriptSegment`, `SpeakerTurn`, `MeetingLanguage`, `TranscriptionEngineID` from Task 2.

- [ ] **Step 1: Write TranscriptionEngine.swift (protocol only, no test needed beyond compilation)**

```swift
import Foundation

public enum TranscriptionError: Error {
    /// Apple Speech assets for the locale missing or not installable.
    case assetUnavailable(String)
    /// WhisperKit model selected but not downloaded yet.
    case modelNotDownloaded(String)
    case failed(String)
}

public protocol TranscriptionEngine: Sendable {
    var id: TranscriptionEngineID { get }
    /// Ensure models/assets for the language are present (may download).
    func prepare(language: MeetingLanguage) async throws
    /// Transcribe a single audio file into timed segments.
    /// onProgress receives 0...1 when determinable, nil for indeterminate ticks.
    func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment]
}
```

- [ ] **Step 2: Write failing SpeakerMerger tests**

Merge rule (from spec): each segment gets the speaker of the turn with **maximum time overlap**; if no turn overlaps, the nearest turn by midpoint distance; if `turns` is empty, segments are returned unchanged.

`SpeakerMergerTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func assignsSpeakerByMaxOverlap() {
    let segments = [
        TranscriptSegment(start: 0, end: 4, text: "hello everyone"),
        TranscriptSegment(start: 4, end: 8, text: "hi bruno"),
    ]
    let turns = [
        SpeakerTurn(start: 0, end: 4.5, speakerID: "S1"),
        SpeakerTurn(start: 4.5, end: 8, speakerID: "S2"),
    ]
    let merged = SpeakerMerger.merge(segments: segments, turns: turns)
    #expect(merged[0].speaker == "S1")
    #expect(merged[1].speaker == "S2") // 3.5s overlap with S2 beats 0.5s with S1
}

@Test func segmentSpanningTwoTurnsTakesLargerShare() {
    let segments = [TranscriptSegment(start: 2, end: 6, text: "crossing")]
    let turns = [
        SpeakerTurn(start: 0, end: 3, speakerID: "S1"),   // 1s overlap
        SpeakerTurn(start: 3, end: 10, speakerID: "S2"),  // 3s overlap
    ]
    #expect(SpeakerMerger.merge(segments: segments, turns: turns)[0].speaker == "S2")
}

@Test func gapSegmentFallsBackToNearestTurn() {
    let segments = [TranscriptSegment(start: 10, end: 11, text: "in a gap")]
    let turns = [
        SpeakerTurn(start: 0, end: 5, speakerID: "S1"),
        SpeakerTurn(start: 20, end: 30, speakerID: "S2"),
    ]
    // midpoint 10.5: distance to S1 interval = 5.5, to S2 = 9.5 → S1
    #expect(SpeakerMerger.merge(segments: segments, turns: turns)[0].speaker == "S1")
}

@Test func emptyTurnsLeavesSegmentsUntouched() {
    let segments = [TranscriptSegment(start: 0, end: 1, text: "solo")]
    let merged = SpeakerMerger.merge(segments: segments, turns: [])
    #expect(merged == segments)
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter SpeakerMerger`
Expected: FAIL — `SpeakerMerger` not defined.

- [ ] **Step 4: Implement SpeakerMerger.swift**

```swift
import Foundation

public enum SpeakerMerger {
    /// Assigns a speaker to each transcript segment from diarization turns.
    /// Max time-overlap wins; zero-overlap segments take the nearest turn
    /// by midpoint-to-interval distance. Empty turns → unchanged segments.
    public static func merge(segments: [TranscriptSegment], turns: [SpeakerTurn]) -> [TranscriptSegment] {
        guard !turns.isEmpty else { return segments }
        return segments.map { segment in
            var segment = segment
            segment.speaker = bestSpeaker(for: segment, in: turns)
            return segment
        }
    }

    private static func bestSpeaker(for segment: TranscriptSegment, in turns: [SpeakerTurn]) -> String {
        var bestOverlap: TimeInterval = 0
        var bestByOverlap: String?
        for turn in turns {
            let overlap = min(segment.end, turn.end) - max(segment.start, turn.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestByOverlap = turn.speakerID
            }
        }
        if let winner = bestByOverlap { return winner }

        let midpoint = (segment.start + segment.end) / 2
        let nearest = turns.min { distance(from: midpoint, to: $0) < distance(from: midpoint, to: $1) }!
        return nearest.speakerID
    }

    private static func distance(from point: TimeInterval, to turn: SpeakerTurn) -> TimeInterval {
        if point < turn.start { return turn.start - point }
        if point > turn.end { return point - turn.end }
        return 0
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter SpeakerMerger`
Expected: 4 PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: TranscriptionEngine protocol and SpeakerMerger"
```

---

### Task 5: AppleSpeechEngine (SpeechAnalyzer)

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Transcription/AppleSpeechEngine.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/AppleSpeechEngineSmokeTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` protocol (Task 4).
- Produces: `AppleSpeechEngine()` conforming to `TranscriptionEngine`, `id == .appleSpeech`.

**API caveat:** SpeechAnalyzer/SpeechTranscriber shipped in macOS 26 — exact symbol names below match WWDC25 API; if a name fails to compile, check the SDK headers (`Speech` module) and adjust the call, not the architecture. The smoke test exists precisely to validate this.

- [ ] **Step 1: Implement AppleSpeechEngine.swift**

```swift
import Foundation
import Speech
import AVFoundation
import NaturalLanguage

public final class AppleSpeechEngine: TranscriptionEngine {
    public let id: TranscriptionEngineID = .appleSpeech

    public init() {}

    public func prepare(language: MeetingLanguage) async throws {
        // Assets are ensured per-run in transcribe(); auto needs both locales available.
        let locales = language == .auto ? ["pt_BR", "en_US"] : [language.localeIdentifier!]
        for identifier in locales {
            let transcriber = SpeechTranscriber(
                locale: Locale(identifier: identifier),
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }

    public func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let resolved = try await resolveLanguage(language, fileURL: fileURL)
        return try await run(fileURL: fileURL, localeIdentifier: resolved, onProgress: onProgress)
    }

    /// For .auto: transcribe the first ~30s in English, classify with
    /// NLLanguageRecognizer, then run the full pass in the detected language.
    private func resolveLanguage(_ language: MeetingLanguage, fileURL: URL) async throws -> String {
        if let identifier = language.localeIdentifier { return identifier }
        let probeSegments = try await run(
            fileURL: fileURL, localeIdentifier: "en_US",
            limitSeconds: 30, onProgress: { _ in }
        )
        let probeText = probeSegments.map(\.text).joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.portuguese, .english]
        recognizer.processString(probeText)
        return recognizer.dominantLanguage == .portuguese ? "pt_BR" : "en_US"
    }

    private func run(
        fileURL: URL,
        localeIdentifier: String,
        limitSeconds: Double? = nil,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)
        let totalSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        let effectiveTotal = limitSeconds.map { min($0, totalSeconds) } ?? totalSeconds

        // Collect results concurrently with feeding the file.
        let collector = Task<[TranscriptSegment], Error> {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                var start = 0.0, end = 0.0
                if let range = result.range {
                    start = range.start.seconds
                    end = range.end.seconds
                }
                if let limit = limitSeconds, start > limit { break }
                segments.append(TranscriptSegment(start: start, end: end, text: text))
                if effectiveTotal > 0 { onProgress(min(end / effectiveTotal, 1.0)) }
            }
            return segments
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw TranscriptionError.failed(String(describing: error))
        }
        return try await collector.value
    }
}
```

- [ ] **Step 2: Compile check**

Run: `swift build --package-path MeetingForgeCore`
Expected: builds. If a `Speech` symbol mismatches the SDK (e.g. `result.range` vs an `audioTimeRange` attribute on `result.text.runs`), fix against the actual headers: `swift build 2>&1 | head -30` shows the exact error; open the SDK interface with Xcode's "Jump to Definition" on `SpeechTranscriber`.

- [ ] **Step 3: Write gated smoke test**

Real transcription needs model assets + real speech audio — gate behind an env var so CI/normal runs skip it.

`AppleSpeechEngineSmokeTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["MF_SMOKE_AUDIO"] != nil))
func transcribesRealAudioFile() async throws {
    // export MF_SMOKE_AUDIO=/path/to/short-speech.m4a before running
    let path = ProcessInfo.processInfo.environment["MF_SMOKE_AUDIO"]!
    let engine = AppleSpeechEngine()
    try await engine.prepare(language: .english)
    let segments = try await engine.transcribe(
        fileURL: URL(fileURLWithPath: path), language: .english, onProgress: { _ in })
    #expect(!segments.isEmpty)
    #expect(segments.allSatisfy { $0.end >= $0.start })
}
```

- [ ] **Step 4: Run suite (smoke skipped), then run smoke manually once**

Run: `swift test --package-path MeetingForgeCore`
Expected: PASS, smoke test skipped.

Then record a 10s voice memo (or any short speech m4a) and run:
`MF_SMOKE_AUDIO=/path/to/speech.m4a swift test --package-path MeetingForgeCore --filter transcribesRealAudioFile`
Expected: PASS with non-empty segments. Fix API-name drift here if it appears.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AppleSpeechEngine using macOS 26 SpeechAnalyzer"
```

---

### Task 6: WhisperKitEngine + model manager

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Transcription/WhisperKitEngine.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/WhisperKitEngineTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` protocol (Task 4).
- Produces:
  - `WhisperKitEngine(modelName: String, modelsDirectory: URL)` conforming to `TranscriptionEngine`, `id == .whisperKit`
  - `WhisperKitModelManager` — `static let recommendedModels: [String]`, `func downloadedModels() -> [String]`, `func isDownloaded(_ name: String) -> Bool`, `func download(_ name: String, progress: @escaping @Sendable (Double) -> Void) async throws`, `func delete(_ name: String) throws`

- [ ] **Step 1: Write failing model-manager tests (filesystem only, no real downloads)**

`WhisperKitEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

@Test func modelManagerListsDownloadedModels() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-wk-\(UUID().uuidString)")
    let manager = WhisperKitModelManager(modelsDirectory: dir)
    #expect(manager.downloadedModels().isEmpty)

    // Simulate a completed download: WhisperKit stores each model as a folder.
    let modelDir = dir.appendingPathComponent("openai_whisper-base")
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    #expect(manager.downloadedModels() == ["openai_whisper-base"])
    #expect(manager.isDownloaded("openai_whisper-base"))
    #expect(!manager.isDownloaded("openai_whisper-large-v3-v20240930_626MB"))

    try manager.delete("openai_whisper-base")
    #expect(manager.downloadedModels().isEmpty)
}

@Test func engineRefusesToRunWithoutDownloadedModel() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-wk-\(UUID().uuidString)")
    let engine = WhisperKitEngine(modelName: "openai_whisper-base", modelsDirectory: dir)
    await #expect(throws: TranscriptionError.self) {
        try await engine.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/nothing.m4a"),
            language: .english, onProgress: { _ in })
    }
}

@Test func recommendedModelsNonEmpty() {
    #expect(WhisperKitModelManager.recommendedModels.contains("openai_whisper-base"))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter WhisperKit`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement WhisperKitEngine.swift**

```swift
import Foundation
import WhisperKit

public final class WhisperKitModelManager: Sendable {
    public let modelsDirectory: URL

    public static let recommendedModels: [String] = [
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-large-v3-v20240930_626MB",
        "openai_whisper-large-v3-turbo",
    ]

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public func downloadedModels() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path))?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
    }

    public func isDownloaded(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(name).path)
    }

    public func download(_ name: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(
            variant: name,
            downloadBase: modelsDirectory,
            progressCallback: { progress($0.fractionCompleted) }
        )
    }

    public func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: modelsDirectory.appendingPathComponent(name))
    }
}

public final class WhisperKitEngine: TranscriptionEngine {
    public let id: TranscriptionEngineID = .whisperKit
    private let modelName: String
    private let manager: WhisperKitModelManager

    public init(modelName: String, modelsDirectory: URL) {
        self.modelName = modelName
        self.manager = WhisperKitModelManager(modelsDirectory: modelsDirectory)
    }

    public func prepare(language: MeetingLanguage) async throws {
        guard manager.isDownloaded(modelName) else {
            throw TranscriptionError.modelNotDownloaded(modelName)
        }
    }

    public func transcribe(
        fileURL: URL,
        language: MeetingLanguage,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> [TranscriptSegment] {
        guard manager.isDownloaded(modelName) else {
            throw TranscriptionError.modelNotDownloaded(modelName)
        }
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: manager.modelsDirectory,
            download: false
        )
        let pipe: WhisperKit
        do {
            pipe = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.failed(String(describing: error))
        }

        var options = DecodingOptions()
        switch language {
        case .portugueseBR: options.language = "pt"; options.detectLanguage = false
        case .english: options.language = "en"; options.detectLanguage = false
        case .auto: options.detectLanguage = true
        }

        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(
                audioPath: fileURL.path,
                decodeOptions: options,
                callback: { progress in
                    onProgress(nil) // WhisperKit callback ticks per segment; indeterminate
                    return nil
                }
            )
        } catch {
            throw TranscriptionError.failed(String(describing: error))
        }

        return results.flatMap { result in
            result.segments.map { seg in
                TranscriptSegment(
                    start: TimeInterval(seg.start),
                    end: TimeInterval(seg.end),
                    text: seg.text.trimmingCharacters(in: .whitespaces)
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter WhisperKit`
Expected: 3 PASS (no network: download() never called in tests).

- [ ] **Step 5: Manual smoke (once, optional but recommended)**

```bash
swift run --package-path MeetingForgeCore 2>/dev/null || true
```
Instead of a runner, verify via the gated pattern from Task 5 if desired; the definitive check happens in app UI (Task 20 Settings downloads a model; Task 18 runs it).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: WhisperKitEngine and model manager"
```

---

### Task 7: DiarizationService (FluidAudio)

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Diarization/DiarizationService.swift`

**Interfaces:**
- Consumes: `SpeakerTurn` (Task 2).
- Produces: `protocol Diarizer: Sendable { func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn] }` and `FluidAudioDiarizer` conforming to it. (`Diarizer` protocol exists so PipelineCoordinator tests can use a fake.)

- [ ] **Step 1: Implement DiarizationService.swift**

```swift
import Foundation
import FluidAudio

public protocol Diarizer: Sendable {
    /// Returns speaker turns for the audio file, speakers labeled "S1", "S2", ...
    func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn]
}

public enum DiarizationError: Error {
    case failed(String)
}

public final class FluidAudioDiarizer: Diarizer {
    public init() {}

    public func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn] {
        do {
            // Models download on first use to FluidAudio's cache dir.
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)

            let samples = try AudioConverter().resampleAudioFile(fileURL) // 16kHz mono Float
            let result = try diarizer.performCompleteDiarization(samples)

            // Map FluidAudio speaker ids (arbitrary strings) to stable "S1","S2",... by first appearance.
            var idMap: [String: String] = [:]
            var turns: [SpeakerTurn] = []
            for segment in result.segments {
                let rawID = String(describing: segment.speakerId)
                if idMap[rawID] == nil {
                    idMap[rawID] = "S\(idMap.count + 1)"
                }
                turns.append(SpeakerTurn(
                    start: TimeInterval(segment.startTimeSeconds),
                    end: TimeInterval(segment.endTimeSeconds),
                    speakerID: idMap[rawID]!
                ))
            }
            return turns.sorted { $0.start < $1.start }
        } catch let error as DiarizationError {
            throw error
        } catch {
            throw DiarizationError.failed(String(describing: error))
        }
    }
}
```

- [ ] **Step 2: Compile check**

Run: `swift build --package-path MeetingForgeCore`
Expected: builds. If FluidAudio's segment property names differ (e.g. `speakerId` vs `speakerID`), fix per compile error — the merge/mapping logic stays.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: FluidAudio diarization service"
```

Note: no unit test — FluidAudio needs real models + real multi-speaker audio. The `Diarizer` protocol boundary is covered by PipelineCoordinator tests (Task 14) with a fake; `SpeakerMerger` (already tested) holds the logic. End-to-end verified in-app.

---

### Task 8: MinutesProvider protocol, PromptBuilder, Transport/SSE

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/MinutesProvider.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/PromptBuilder.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/Transport.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/PromptBuilderTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/SSEParserTests.swift`

**Interfaces:**
- Consumes: `ProviderID`, `UsageStats`, `TranscriptSegment`, `MeetingTemplate` (Task 2).
- Produces (all provider tasks depend on these exact shapes):

```swift
public struct MinutesRequest: Sendable {
    public var systemPrompt: String
    public var userPrompt: String
    public var model: String
    public var apiKey: String?
    public init(systemPrompt: String, userPrompt: String, model: String, apiKey: String? = nil)
}

public enum MinutesEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(UsageStats)
}

public enum ProviderError: Error {
    case missingAPIKey(ProviderID)
    case http(status: Int, message: String)
    case malformedResponse(String)
    case executableNotFound(String)   // Claude Code
    case cliFailure(String)           // Claude Code
}

public protocol MinutesProvider: Sendable {
    var id: ProviderID { get }
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error>
    func listModels(apiKey: String?) async throws -> [String]
}

public protocol StreamTransport: Sendable {
    /// Performs the request and returns response headers + an async stream of body LINES.
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
}

public struct URLSessionTransport: StreamTransport { public init() }

public enum SSEParser {
    /// "data: {...}" → payload; ignores comments/blank lines; "[DONE]" → nil (skip).
    public static func payload(fromLine line: String) -> String?
}

public enum PromptBuilder {
    public static func build(
        template: TemplateContent, transcript: [TranscriptSegment],
        speakerNames: [String: String], diarized: Bool
    ) -> (system: String, user: String)
}

/// Plain value mirror of MeetingTemplate so Core APIs don't need SwiftData.
public struct TemplateContent: Sendable {
    public var name: String
    public var systemPrompt: String
    public var sections: [String]
    public init(name: String, systemPrompt: String, sections: [String])
}
```

- [ ] **Step 1: Write failing PromptBuilder tests**

Rules: system = template.systemPrompt + section list + language rule ("Write the minutes in the same language as the transcript."). User = transcript rendered as `[mm:ss] Name: text` lines when diarized (names resolved via `speakerNames`, falling back to raw ID), plain `[mm:ss] text` otherwise.

`PromptBuilderTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

let template = TemplateContent(
    name: "Business",
    systemPrompt: "You are an expert minute-taker.",
    sections: ["Summary", "Action Points", "Questions"]
)

@Test func systemPromptContainsSectionsAndLanguageRule() {
    let (system, _) = PromptBuilder.build(template: template, transcript: [], speakerNames: [:], diarized: false)
    #expect(system.contains("You are an expert minute-taker."))
    #expect(system.contains("Summary"))
    #expect(system.contains("Action Points"))
    #expect(system.contains("same language as the transcript"))
}

@Test func diarizedTranscriptUsesRenamedSpeakers() {
    let segments = [
        TranscriptSegment(start: 0, end: 2, text: "bom dia", speaker: "S1"),
        TranscriptSegment(start: 62, end: 65, text: "olá", speaker: "S2"),
    ]
    let (_, user) = PromptBuilder.build(
        template: template, transcript: segments,
        speakerNames: ["S1": "Bruno"], diarized: true)
    #expect(user.contains("[00:00] Bruno: bom dia"))
    #expect(user.contains("[01:02] S2: olá")) // unrenamed falls back to raw ID
}

@Test func plainTranscriptOmitsSpeakers() {
    let segments = [TranscriptSegment(start: 125, end: 130, text: "next topic", speaker: "S1")]
    let (_, user) = PromptBuilder.build(template: template, transcript: segments, speakerNames: [:], diarized: false)
    #expect(user.contains("[02:05] next topic"))
    #expect(!user.contains("S1"))
}
```

- [ ] **Step 2: Write failing SSEParser tests**

`SSEParserTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func extractsDataPayload() {
    #expect(SSEParser.payload(fromLine: "data: {\"x\":1}") == "{\"x\":1}")
    #expect(SSEParser.payload(fromLine: "data:{\"x\":1}") == "{\"x\":1}")
}

@Test func skipsNoise() {
    #expect(SSEParser.payload(fromLine: "") == nil)
    #expect(SSEParser.payload(fromLine: ": keep-alive") == nil)
    #expect(SSEParser.payload(fromLine: "event: message_start") == nil)
    #expect(SSEParser.payload(fromLine: "data: [DONE]") == nil)
}
```

- [ ] **Step 3: Run to verify failures**

Run: `swift test --package-path MeetingForgeCore --filter 'PromptBuilder|SSEParser'`
Expected: FAIL — types not defined.

- [ ] **Step 4: Implement the three source files**

`MinutesProvider.swift`:

```swift
import Foundation

public struct MinutesRequest: Sendable {
    public var systemPrompt: String
    public var userPrompt: String
    public var model: String
    public var apiKey: String?

    public init(systemPrompt: String, userPrompt: String, model: String, apiKey: String? = nil) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.model = model
        self.apiKey = apiKey
    }
}

public enum MinutesEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(UsageStats)
}

public enum ProviderError: Error {
    case missingAPIKey(ProviderID)
    case http(status: Int, message: String)
    case malformedResponse(String)
    case executableNotFound(String)
    case cliFailure(String)
}

public protocol MinutesProvider: Sendable {
    var id: ProviderID { get }
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error>
    func listModels(apiKey: String?) async throws -> [String]
}
```

`Transport.swift`:

```swift
import Foundation

public protocol StreamTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
}

public struct URLSessionTransport: StreamTransport {
    public init() {}

    public func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("non-HTTP response")
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
    }
}

public enum SSEParser {
    public static func payload(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return payload
    }
}

/// Shared helper: read an error body from a line stream and throw ProviderError.http.
func throwHTTPError(status: Int, lines: AsyncThrowingStream<String, Error>) async throws -> Never {
    var body = ""
    for try await line in lines { body += line; if body.count > 4000 { break } }
    throw ProviderError.http(status: status, message: body)
}
```

`PromptBuilder.swift`:

```swift
import Foundation

public struct TemplateContent: Sendable {
    public var name: String
    public var systemPrompt: String
    public var sections: [String]

    public init(name: String, systemPrompt: String, sections: [String]) {
        self.name = name
        self.systemPrompt = systemPrompt
        self.sections = sections
    }
}

public enum PromptBuilder {
    public static func build(
        template: TemplateContent,
        transcript: [TranscriptSegment],
        speakerNames: [String: String],
        diarized: Bool
    ) -> (system: String, user: String) {
        let sectionList = template.sections.map { "- \($0)" }.joined(separator: "\n")
        let system = """
        \(template.systemPrompt)

        Produce meeting minutes in Markdown with exactly these sections (use ## headings, keep this order, omit a section only if truly empty):
        \(sectionList)

        Write the minutes in the same language as the transcript.
        """

        let lines = transcript.map { segment -> String in
            let stamp = timestamp(segment.start)
            if diarized, let raw = segment.speaker {
                let name = speakerNames[raw] ?? raw
                return "[\(stamp)] \(name): \(segment.text)"
            }
            return "[\(stamp)] \(segment.text)"
        }
        let user = """
        Transcript of the meeting:

        \(lines.joined(separator: "\n"))
        """
        return (system, user)
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter 'PromptBuilder|SSEParser'`
Expected: 5 PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: MinutesProvider protocol, PromptBuilder, SSE transport"
```

---

### Task 9: OpenAIProvider + AnthropicProvider

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/OpenAIProvider.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/AnthropicProvider.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/OpenAIProviderTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/AnthropicProviderTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/MockTransport.swift`

**Interfaces:**
- Consumes: everything from Task 8.
- Produces: `OpenAIProvider(transport: StreamTransport = URLSessionTransport())`, `AnthropicProvider(transport: ...)` — both `MinutesProvider`.

- [ ] **Step 1: Write MockTransport (shared by all provider tests)**

`MockTransport.swift`:

```swift
import Foundation
@testable import MeetingForgeCore

struct MockTransport: StreamTransport {
    var status: Int = 200
    var bodyLines: [String]
    /// Captures the last request for assertions.
    let captured = CapturedRequest()

    final class CapturedRequest: @unchecked Sendable {
        var request: URLRequest?
    }

    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        captured.request = request
        let http = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        let lines = bodyLines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
        return (http, stream)
    }
}

/// Drains a provider stream into (text, usage) for test assertions.
func drain(_ stream: AsyncThrowingStream<MinutesEvent, Error>) async throws -> (String, UsageStats?) {
    var text = ""
    var usage: UsageStats?
    for try await event in stream {
        switch event {
        case .textDelta(let delta): text += delta
        case .completed(let stats): usage = stats
        }
    }
    return (text, usage)
}
```

- [ ] **Step 2: Write failing OpenAI tests**

`OpenAIProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript here", model: "gpt-5.2", apiKey: "sk-test")

@Test func openAIStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        #"data: {"choices":[{"delta":{"content":"# Ata"}}]}"#,
        #"data: {"choices":[{"delta":{"content":" de reunião"}}]}"#,
        #"data: {"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":45}}"#,
        "data: [DONE]",
    ])
    let provider = OpenAIProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata de reunião")
    #expect(usage == UsageStats(inputTokens: 120, outputTokens: 45))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(body["model"] as? String == "gpt-5.2")
    #expect(body["stream"] as? Bool == true)
    #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
}

@Test func openAIMissingKeyThrows() async {
    let provider = OpenAIProvider(transport: MockTransport(bodyLines: []))
    var req = request; req.apiKey = nil
    await #expect(throws: ProviderError.self) { _ = try await provider.generate(req) }
}

@Test func openAIHTTPErrorSurfacesBody() async throws {
    let transport = MockTransport(status: 429, bodyLines: [#"{"error":{"message":"rate limited"}}"#])
    let provider = OpenAIProvider(transport: transport)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func openAIListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"data":[{"id":"gpt-5.2"},{"id":"gpt-5-mini"},{"id":"whisper-1"}]}"#
    ])
    let provider = OpenAIProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "sk-test")
    #expect(models.contains("gpt-5.2"))
    #expect(transport.captured.request?.url?.absoluteString == "https://api.openai.com/v1/models")
}
```

- [ ] **Step 3: Write failing Anthropic tests**

`AnthropicProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "claude-sonnet-4-5", apiKey: "ak-test")

@Test func anthropicStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        "event: message_start",
        #"data: {"type":"message_start","message":{"usage":{"input_tokens":200,"output_tokens":1}}}"#,
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"# Minutes"}}"#,
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" done"}}"#,
        "event: message_delta",
        #"data: {"type":"message_delta","usage":{"output_tokens":77}}"#,
        "event: message_stop",
        #"data: {"type":"message_stop"}"#,
    ])
    let provider = AnthropicProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Minutes done")
    #expect(usage == UsageStats(inputTokens: 200, outputTokens: 77))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(req.value(forHTTPHeaderField: "x-api-key") == "ak-test")
    #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(body["system"] as? String == "sys")
    #expect(body["max_tokens"] as? Int == 8192)
}

@Test func anthropicListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"data":[{"id":"claude-sonnet-4-5"},{"id":"claude-haiku-4-5"}]}"#
    ])
    let provider = AnthropicProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "ak-test")
    #expect(models == ["claude-sonnet-4-5", "claude-haiku-4-5"])
}
```

- [ ] **Step 4: Run to verify failures**

Run: `swift test --package-path MeetingForgeCore --filter 'OpenAIProvider|AnthropicProvider'`
Expected: FAIL — providers not defined.

- [ ] **Step 5: Implement OpenAIProvider.swift**

```swift
import Foundation

public struct OpenAIProvider: MinutesProvider {
    public let id: ProviderID = .openAI
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt],
            ],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var usage: UsageStats?
                do {
                    for try await line in lines {
                        guard let payload = SSEParser.payload(fromLine: line),
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
                        else { continue }
                        if let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if let u = json["usage"] as? [String: Any],
                           let input = u["prompt_tokens"] as? Int,
                           let output = u["completion_tokens"] as? Int {
                            usage = UsageStats(inputTokens: input, outputTokens: output)
                        }
                    }
                    continuation.yield(.completed(usage ?? UsageStats(inputTokens: 0, outputTokens: 0)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        guard let apiKey, !apiKey.isEmpty else { throw ProviderError.missingAPIKey(id) }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("models"))
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return data.compactMap { $0["id"] as? String }
    }
}
```

- [ ] **Step 6: Implement AnthropicProvider.swift**

```swift
import Foundation

public struct AnthropicProvider: MinutesProvider {
    public let id: ProviderID = .anthropic
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://api.anthropic.com/v1")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "max_tokens": 8192,
            "stream": true,
            "system": request.systemPrompt,
            "messages": [["role": "user", "content": request.userPrompt]],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var inputTokens = 0
                var outputTokens = 0
                do {
                    for try await line in lines {
                        guard let payload = SSEParser.payload(fromLine: line),
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let type = json["type"] as? String
                        else { continue }
                        switch type {
                        case "message_start":
                            if let message = json["message"] as? [String: Any],
                               let u = message["usage"] as? [String: Any] {
                                inputTokens = u["input_tokens"] as? Int ?? 0
                            }
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(.textDelta(text))
                            }
                        case "message_delta":
                            if let u = json["usage"] as? [String: Any],
                               let output = u["output_tokens"] as? Int {
                                outputTokens = output
                            }
                        default:
                            break
                        }
                    }
                    continuation.yield(.completed(UsageStats(inputTokens: inputTokens, outputTokens: outputTokens)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        guard let apiKey, !apiKey.isEmpty else { throw ProviderError.missingAPIKey(id) }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("models"))
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return data.compactMap { $0["id"] as? String }
    }
}
```

- [ ] **Step 7: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter 'OpenAIProvider|AnthropicProvider'`
Expected: 6 PASS.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: OpenAI and Anthropic streaming providers"
```

---

### Task 10: GeminiProvider + OllamaCloudProvider

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/GeminiProvider.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/OllamaCloudProvider.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/GeminiProviderTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/OllamaCloudProviderTests.swift`

**Interfaces:**
- Consumes: Task 8 types + `MockTransport`/`drain` from Task 9.
- Produces: `GeminiProvider(transport:)`, `OllamaCloudProvider(transport:)` — both `MinutesProvider`.

- [ ] **Step 1: Write failing Gemini tests**

Gemini streaming endpoint: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse` with header `x-goog-api-key`. SSE payloads carry `candidates[0].content.parts[].text` and final `usageMetadata`.

`GeminiProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "gemini-2.5-pro", apiKey: "g-test")

@Test func geminiStreamsTextAndUsage() async throws {
    let transport = MockTransport(bodyLines: [
        #"data: {"candidates":[{"content":{"parts":[{"text":"# Ata"}]}}]}"#,
        #"data: {"candidates":[{"content":{"parts":[{"text":" final"}]}}],"usageMetadata":{"promptTokenCount":300,"candidatesTokenCount":90}}"#,
    ])
    let provider = GeminiProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata final")
    #expect(usage == UsageStats(inputTokens: 300, outputTokens: 90))

    let req = transport.captured.request!
    #expect(req.url!.absoluteString.contains("models/gemini-2.5-pro:streamGenerateContent"))
    #expect(req.url!.absoluteString.contains("alt=sse"))
    #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-test")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    let sys = body["systemInstruction"] as! [String: Any]
    #expect(((sys["parts"] as! [[String: Any]])[0]["text"] as! String) == "sys")
}

@Test func geminiListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"models":[{"name":"models/gemini-2.5-pro","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding-001","supportedGenerationMethods":["embedContent"]}]}"#
    ])
    let provider = GeminiProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "g-test")
    #expect(models == ["gemini-2.5-pro"]) // strips "models/" prefix, filters non-generateContent
}
```

- [ ] **Step 2: Write failing Ollama Cloud tests**

Ollama Cloud: `POST https://ollama.com/api/chat`, `Authorization: Bearer <key>`, streaming **JSON lines** (not SSE). Final line has `"done":true` + `prompt_eval_count`/`eval_count`.

`OllamaCloudProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

private let request = MinutesRequest(
    systemPrompt: "sys", userPrompt: "transcript", model: "gpt-oss:120b", apiKey: "ol-test")

@Test func ollamaStreamsJSONLines() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"message":{"role":"assistant","content":"# Minutes"},"done":false}"#,
        #"{"message":{"role":"assistant","content":" end"},"done":false}"#,
        #"{"message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":500,"eval_count":150}"#,
    ])
    let provider = OllamaCloudProvider(transport: transport)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Minutes end")
    #expect(usage == UsageStats(inputTokens: 500, outputTokens: 150))

    let req = transport.captured.request!
    #expect(req.url?.absoluteString == "https://ollama.com/api/chat")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer ol-test")
}

@Test func ollamaListsModels() async throws {
    let transport = MockTransport(bodyLines: [
        #"{"models":[{"name":"gpt-oss:120b"},{"name":"deepseek-v3.1:671b"}]}"#
    ])
    let provider = OllamaCloudProvider(transport: transport)
    let models = try await provider.listModels(apiKey: "ol-test")
    #expect(models == ["gpt-oss:120b", "deepseek-v3.1:671b"])
    #expect(transport.captured.request?.url?.absoluteString == "https://ollama.com/api/tags")
}
```

- [ ] **Step 3: Run to verify failures**

Run: `swift test --package-path MeetingForgeCore --filter 'GeminiProvider|OllamaCloud'`
Expected: FAIL.

- [ ] **Step 4: Implement GeminiProvider.swift**

```swift
import Foundation

public struct GeminiProvider: MinutesProvider {
    public let id: ProviderID = .gemini
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models/\(request.model):streamGenerateContent"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": request.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": request.userPrompt]]]],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var usage: UsageStats?
                do {
                    for try await line in lines {
                        guard let payload = SSEParser.payload(fromLine: line),
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
                        else { continue }
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let content = candidates.first?["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]] {
                            for part in parts {
                                if let text = part["text"] as? String, !text.isEmpty {
                                    continuation.yield(.textDelta(text))
                                }
                            }
                        }
                        if let meta = json["usageMetadata"] as? [String: Any],
                           let input = meta["promptTokenCount"] as? Int {
                            usage = UsageStats(
                                inputTokens: input,
                                outputTokens: meta["candidatesTokenCount"] as? Int ?? 0)
                        }
                    }
                    continuation.yield(.completed(usage ?? UsageStats(inputTokens: 0, outputTokens: 0)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        guard let apiKey, !apiKey.isEmpty else { throw ProviderError.missingAPIKey(id) }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("models"))
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return models.compactMap { model in
            guard let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent"),
                  let name = model["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
    }
}
```

- [ ] **Step 5: Implement OllamaCloudProvider.swift**

```swift
import Foundation

public struct OllamaCloudProvider: MinutesProvider {
    public let id: ProviderID = .ollamaCloud
    let transport: StreamTransport
    let baseURL: URL

    public init(transport: StreamTransport = URLSessionTransport(),
                baseURL: URL = URL(string: "https://ollama.com")!) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let apiKey = request.apiKey, !apiKey.isEmpty else {
            throw ProviderError.missingAPIKey(id)
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": request.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt],
            ],
        ] as [String: Any])

        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var usage: UsageStats?
                do {
                    for try await line in lines {
                        // Ollama streams raw JSON objects, one per line (no SSE framing).
                        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                        else { continue }
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if json["done"] as? Bool == true {
                            usage = UsageStats(
                                inputTokens: json["prompt_eval_count"] as? Int ?? 0,
                                outputTokens: json["eval_count"] as? Int ?? 0)
                        }
                    }
                    continuation.yield(.completed(usage ?? UsageStats(inputTokens: 0, outputTokens: 0)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        guard let apiKey, !apiKey.isEmpty else { throw ProviderError.missingAPIKey(id) }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (http, lines) = try await transport.lines(for: urlRequest)
        guard http.statusCode == 200 else { try await throwHTTPError(status: http.statusCode, lines: lines) }
        var body = ""
        for try await line in lines { body += line }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("models list")
        }
        return models.compactMap { $0["name"] as? String }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter 'GeminiProvider|OllamaCloud'`
Expected: 4 PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: Gemini and Ollama Cloud streaming providers"
```

---

### Task 11: ClaudeCodeProvider (subprocess)

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/ClaudeCodeProvider.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/ClaudeCodeProviderTests.swift`

**Interfaces:**
- Consumes: Task 8 types.
- Produces: `ClaudeCodeProvider(executableURL: URL?)` — `MinutesProvider`. Also `ClaudeCodeProvider.detectExecutable() -> URL?` (checks `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, then `which claude` via `/usr/bin/env`).

**Behavior:** runs `claude -p --output-format json --model <model>`, prompt via stdin (system prompt prepended to user prompt — CLI has no separate system field for this use). Parses single JSON object from stdout: `result` (string), `usage.input_tokens`, `usage.output_tokens`, `total_cost_usd`, `is_error`. Emits one `.textDelta(result)` then `.completed(usage with reportedCostUSD)`. No streaming.

- [ ] **Step 1: Write failing tests using a stub executable**

`ClaudeCodeProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

/// Writes an executable shell script that ignores stdin and prints canned JSON.
func makeStubCLI(json: String, exitCode: Int = 0) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-claude-stub-\(UUID().uuidString)")
    let script = """
    #!/bin/sh
    cat > /dev/null
    cat <<'EOF'
    \(json)
    EOF
    exit \(exitCode)
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private let request = MinutesRequest(
    systemPrompt: "You are a minute-taker.", userPrompt: "transcript", model: "sonnet")

@Test func parsesCLIResultAndUsage() async throws {
    let stub = try makeStubCLI(json: #"""
    {"type":"result","subtype":"success","is_error":false,"result":"# Ata\n\n- ponto 1","total_cost_usd":0.0042,"usage":{"input_tokens":900,"output_tokens":210}}
    """#)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let (text, usage) = try await drain(try await provider.generate(request))
    #expect(text == "# Ata\n\n- ponto 1")
    #expect(usage?.inputTokens == 900)
    #expect(usage?.outputTokens == 210)
    #expect(usage?.reportedCostUSD == 0.0042)
}

@Test func cliErrorResultThrows() async throws {
    let stub = try makeStubCLI(json: #"{"type":"result","is_error":true,"result":"overloaded"}"#)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func nonZeroExitThrows() async throws {
    let stub = try makeStubCLI(json: "boom", exitCode: 3)
    let provider = ClaudeCodeProvider(executableURL: stub)
    let stream = try await provider.generate(request)
    await #expect(throws: ProviderError.self) { _ = try await drain(stream) }
}

@Test func missingExecutableThrows() async {
    let provider = ClaudeCodeProvider(executableURL: nil)
    await #expect(throws: ProviderError.self) { _ = try await provider.generate(request) }
}

@Test func staticModelList() async throws {
    let provider = ClaudeCodeProvider(executableURL: nil)
    let models = try await provider.listModels(apiKey: nil)
    #expect(models == ["sonnet", "opus", "haiku"])
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter ClaudeCode`
Expected: FAIL.

- [ ] **Step 3: Implement ClaudeCodeProvider.swift**

```swift
import Foundation

public struct ClaudeCodeProvider: MinutesProvider {
    public let id: ProviderID = .claudeCode
    let executableURL: URL?

    public init(executableURL: URL?) {
        self.executableURL = executableURL
    }

    public static func detectExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to `which` through the user's login shell PATH.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        guard let executableURL else {
            throw ProviderError.executableNotFound("claude CLI not found — install Claude Code or set the path in Settings")
        }
        let prompt = """
        \(request.systemPrompt)

        \(request.userPrompt)
        """
        let model = request.model

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = ["-p", "--output-format", "json", "--model", model]
                    let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
                    process.standardInput = stdinPipe
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(Data(prompt.utf8))
                    try stdinPipe.fileHandleForWriting.close()

                    let stdout = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
                    let stderr = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        throw ProviderError.cliFailure(
                            String(data: stderr, encoding: .utf8) ?? "exit \(process.terminationStatus)")
                    }
                    guard let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] else {
                        throw ProviderError.malformedResponse(
                            String(data: stdout, encoding: .utf8) ?? "empty stdout")
                    }
                    if json["is_error"] as? Bool == true {
                        throw ProviderError.cliFailure(json["result"] as? String ?? "unknown CLI error")
                    }
                    guard let result = json["result"] as? String else {
                        throw ProviderError.malformedResponse("missing result field")
                    }
                    let usageDict = json["usage"] as? [String: Any] ?? [:]
                    let usage = UsageStats(
                        inputTokens: usageDict["input_tokens"] as? Int ?? 0,
                        outputTokens: usageDict["output_tokens"] as? Int ?? 0,
                        reportedCostUSD: json["total_cost_usd"] as? Double)
                    continuation.yield(.textDelta(result))
                    continuation.yield(.completed(usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(apiKey: String?) async throws -> [String] {
        ["sonnet", "opus", "haiku"]
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter ClaudeCode`
Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Claude Code CLI provider via subprocess"
```

---

### Task 12: ModelCatalog + CostCalculator

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/ModelCatalog.swift`
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Providers/CostCalculator.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/ModelCatalogTests.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/CostCalculatorTests.swift`

**Interfaces:**
- Consumes: `MinutesProvider.listModels` (Tasks 9–11), `UsageStats`, `ProviderID`.
- Produces:
  - `ModelCatalog(defaults: UserDefaults)` — `func models(for provider: MinutesProvider, apiKey: String?, forceRefresh: Bool) async throws -> [String]` (24h cache in UserDefaults, key `model-cache-<providerID>`)
  - `struct ModelPrice: Codable, Equatable { var inputPerMTok: Double; var outputPerMTok: Double }`
  - `CostCalculator(overrides: [String: ModelPrice])` — `func cost(model: String, usage: UsageStats) -> Double?`; `static let defaultPrices: [String: ModelPrice]` (longest-prefix match; `usage.reportedCostUSD` always wins; unknown model → nil)

- [ ] **Step 1: Write failing CostCalculator tests**

`CostCalculatorTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func reportedCostWins() {
    let calc = CostCalculator()
    let usage = UsageStats(inputTokens: 1_000_000, outputTokens: 0, reportedCostUSD: 0.5)
    #expect(calc.cost(model: "whatever", usage: usage) == 0.5)
}

@Test func prefixMatchComputesCost() {
    let calc = CostCalculator(overrides: ["gpt-5.2": ModelPrice(inputPerMTok: 2.0, outputPerMTok: 8.0)])
    let usage = UsageStats(inputTokens: 500_000, outputTokens: 250_000)
    // 0.5 * 2.0 + 0.25 * 8.0 = 3.0
    #expect(calc.cost(model: "gpt-5.2-2026-06-01", usage: usage) == 3.0)
}

@Test func longestPrefixWins() {
    let calc = CostCalculator(overrides: [
        "claude": ModelPrice(inputPerMTok: 1, outputPerMTok: 1),
        "claude-sonnet-4-5": ModelPrice(inputPerMTok: 3, outputPerMTok: 15),
    ])
    let usage = UsageStats(inputTokens: 1_000_000, outputTokens: 0)
    #expect(calc.cost(model: "claude-sonnet-4-5-20260101", usage: usage) == 3.0)
}

@Test func unknownModelReturnsNil() {
    let calc = CostCalculator(overrides: [:])
    // Wipe defaults influence by using a model name no default table entry prefixes.
    #expect(calc.cost(model: "totally-unknown-model-xyz",
                      usage: UsageStats(inputTokens: 10, outputTokens: 10)) == nil)
}

@Test func defaultTableCoversCommonModels() {
    #expect(CostCalculator.defaultPrices.keys.contains("gpt-5"))
    #expect(CostCalculator.defaultPrices.keys.contains("claude-sonnet-4-5"))
    #expect(CostCalculator.defaultPrices.keys.contains("gemini-2.5-pro"))
}
```

- [ ] **Step 2: Write failing ModelCatalog tests**

`ModelCatalogTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

/// MinutesProvider fake that counts listModels calls.
final class CountingProvider: MinutesProvider, @unchecked Sendable {
    let id: ProviderID = .openAI
    var calls = 0
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        fatalError("unused")
    }
    func listModels(apiKey: String?) async throws -> [String] {
        calls += 1
        return ["model-a", "model-b"]
    }
}

@Test func cachesModelList() async throws {
    let suite = "mf-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let catalog = ModelCatalog(defaults: defaults)
    let provider = CountingProvider()

    let first = try await catalog.models(for: provider, apiKey: "k", forceRefresh: false)
    let second = try await catalog.models(for: provider, apiKey: "k", forceRefresh: false)
    #expect(first == ["model-a", "model-b"])
    #expect(second == first)
    #expect(provider.calls == 1) // second came from cache

    _ = try await catalog.models(for: provider, apiKey: "k", forceRefresh: true)
    #expect(provider.calls == 2)
}
```

- [ ] **Step 3: Run to verify failures**

Run: `swift test --package-path MeetingForgeCore --filter 'CostCalculator|ModelCatalog'`
Expected: FAIL.

- [ ] **Step 4: Implement CostCalculator.swift**

Default prices: verify against provider pricing pages at implementation time; these are editable in Settings (Task 20) so staleness is recoverable.

```swift
import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double

    public init(inputPerMTok: Double, outputPerMTok: Double) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }
}

public struct CostCalculator: Sendable {
    /// Prefix-keyed price table (USD per million tokens). Longest matching prefix wins.
    public static let defaultPrices: [String: ModelPrice] = [
        // OpenAI
        "gpt-5": ModelPrice(inputPerMTok: 1.25, outputPerMTok: 10.0),
        "gpt-5-mini": ModelPrice(inputPerMTok: 0.25, outputPerMTok: 2.0),
        "gpt-4o": ModelPrice(inputPerMTok: 2.5, outputPerMTok: 10.0),
        // Anthropic
        "claude-sonnet-4-5": ModelPrice(inputPerMTok: 3.0, outputPerMTok: 15.0),
        "claude-haiku-4-5": ModelPrice(inputPerMTok: 1.0, outputPerMTok: 5.0),
        "claude-opus-4": ModelPrice(inputPerMTok: 15.0, outputPerMTok: 75.0),
        // Google
        "gemini-2.5-pro": ModelPrice(inputPerMTok: 1.25, outputPerMTok: 10.0),
        "gemini-2.5-flash": ModelPrice(inputPerMTok: 0.30, outputPerMTok: 2.5),
    ]

    let table: [String: ModelPrice]

    public init(overrides: [String: ModelPrice]? = nil) {
        if let overrides, !overrides.isEmpty {
            self.table = Self.defaultPrices.merging(overrides) { _, override in override }
                .merging(overrides) { existing, _ in existing }
        } else {
            self.table = Self.defaultPrices
        }
    }

    public func cost(model: String, usage: UsageStats) -> Double? {
        if let reported = usage.reportedCostUSD { return reported }
        let match = table.keys
            .filter { model.hasPrefix($0) }
            .max { $0.count < $1.count }
        guard let match, let price = table[match] else { return nil }
        return Double(usage.inputTokens) / 1_000_000 * price.inputPerMTok
             + Double(usage.outputTokens) / 1_000_000 * price.outputPerMTok
    }
}
```

Note on `unknownModelReturnsNil` test: `CostCalculator(overrides: [:])` falls back to the default table, so the test model name must not prefix-match any default key — `totally-unknown-model-xyz` doesn't.

- [ ] **Step 5: Implement ModelCatalog.swift**

```swift
import Foundation

public final class ModelCatalog: Sendable {
    private let defaults: UserDefaults
    private let maxAge: TimeInterval

    public init(defaults: UserDefaults = .standard, maxAge: TimeInterval = 24 * 3600) {
        self.defaults = defaults
        self.maxAge = maxAge
    }

    private struct CacheEntry: Codable {
        var models: [String]
        var fetchedAt: Date
    }

    public func models(for provider: MinutesProvider, apiKey: String?, forceRefresh: Bool) async throws -> [String] {
        let key = "model-cache-\(provider.id.rawValue)"
        if !forceRefresh,
           let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
           Date.now.timeIntervalSince(entry.fetchedAt) < maxAge {
            return entry.models
        }
        let models = try await provider.listModels(apiKey: apiKey)
        let entry = CacheEntry(models: models, fetchedAt: .now)
        defaults.set(try? JSONEncoder().encode(entry), forKey: key)
        return models
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter 'CostCalculator|ModelCatalog'`
Expected: 6 PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: model catalog with cache and cost calculator"
```

---

### Task 13: KeychainStore

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Security/KeychainStore.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/KeychainStoreTests.swift`

**Interfaces:**
- Produces: `KeychainStore(service: String)` — `func set(_ value: String, account: String) throws`, `func get(account: String) -> String?`, `func delete(account: String) throws`. App uses service `com.funnietech.meetingforge`, account = `ProviderID.rawValue`.

- [ ] **Step 1: Write failing tests**

`KeychainStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

@Test func setGetOverwriteDelete() throws {
    let store = KeychainStore(service: "com.funnietech.meetingforge.tests")
    let account = "test-\(UUID().uuidString)"
    defer { try? store.delete(account: account) }

    #expect(store.get(account: account) == nil)
    try store.set("secret-1", account: account)
    #expect(store.get(account: account) == "secret-1")
    try store.set("secret-2", account: account) // overwrite
    #expect(store.get(account: account) == "secret-2")
    try store.delete(account: account)
    #expect(store.get(account: account) == nil)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter Keychain`
Expected: FAIL.

- [ ] **Step 3: Implement KeychainStore.swift**

```swift
import Foundation
import Security

public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    public func set(_ value: String, account: String) throws {
        try? delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter Keychain`
Expected: PASS. (Runs against the real login keychain locally; test cleans up after itself.)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: KeychainStore for provider API keys"
```

---

### Task 14: PipelineCoordinator

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Pipeline/PipelineCoordinator.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/PipelineCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AudioCombiner` (Task 3), `TranscriptionEngine` (Task 4), `Diarizer` (Task 7), `MinutesProvider` + `PromptBuilder` + `TemplateContent` (Task 8).
- Produces:

```swift
public enum PipelineStage: String, Sendable { case combining, transcribing, diarizing, generating }

public enum PipelineEvent: Sendable {
    case stageChanged(PipelineStage)
    case combined(url: URL, duration: TimeInterval)
    case transcribed(segments: [TranscriptSegment], wallTime: TimeInterval)
    case diarized(segments: [TranscriptSegment])   // segments with speakers merged
    case minutesDelta(String)
    case minutesCompleted(markdown: String, usage: UsageStats, latency: TimeInterval)
}

public struct PipelineError: Error {
    public let stage: PipelineStage
    public let underlying: Error
}

public struct PipelineConfig: Sendable {
    public var sourceFiles: [URL]
    public var workDirectory: URL       // combined.m4a written here
    public var language: MeetingLanguage
    public var diarize: Bool
    public var template: TemplateContent
    public var speakerNames: [String: String]
    public var model: String
    public var apiKey: String?
    public init(sourceFiles: [URL], workDirectory: URL, language: MeetingLanguage,
                diarize: Bool, template: TemplateContent,
                speakerNames: [String: String] = [:], model: String, apiKey: String? = nil)
}

public struct PipelineCoordinator: Sendable {
    public init(engine: TranscriptionEngine, diarizer: Diarizer, provider: MinutesProvider)
    /// Full run: combine → transcribe → [diarize] → generate.
    public func run(_ config: PipelineConfig) -> AsyncThrowingStream<PipelineEvent, Error>
    /// Regenerate minutes only, from an existing transcript (retry / new provider / new template).
    public func generateOnly(_ config: PipelineConfig, segments: [TranscriptSegment], diarized: Bool)
        -> AsyncThrowingStream<PipelineEvent, Error>
}
```

- [ ] **Step 1: Write failing tests with fakes**

`PipelineCoordinatorTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingForgeCore

struct FakeEngine: TranscriptionEngine {
    let id: TranscriptionEngineID = .appleSpeech
    var segments: [TranscriptSegment] = [TranscriptSegment(start: 0, end: 2, text: "hello world")]
    var error: TranscriptionError?
    func prepare(language: MeetingLanguage) async throws {}
    func transcribe(fileURL: URL, language: MeetingLanguage,
                    onProgress: @escaping @Sendable (Double?) -> Void) async throws -> [TranscriptSegment] {
        if let error { throw error }
        return segments
    }
}

struct FakeDiarizer: Diarizer {
    var turns: [SpeakerTurn] = [SpeakerTurn(start: 0, end: 5, speakerID: "S1")]
    func speakerTurns(fileURL: URL) async throws -> [SpeakerTurn] { turns }
}

struct FakeProvider: MinutesProvider {
    let id: ProviderID = .openAI
    var chunks: [String] = ["# Minutes", " body"]
    var usage = UsageStats(inputTokens: 10, outputTokens: 5)
    func generate(_ request: MinutesRequest) async throws -> AsyncThrowingStream<MinutesEvent, Error> {
        let chunks = chunks, usage = usage
        return AsyncThrowingStream { c in
            for chunk in chunks { c.yield(.textDelta(chunk)) }
            c.yield(.completed(usage))
            c.finish()
        }
    }
    func listModels(apiKey: String?) async throws -> [String] { [] }
}

func fixtureConfig(diarize: Bool, files: Int = 1) throws -> PipelineConfig {
    var urls: [URL] = []
    for i in 0..<files {
        urls.append(try makeWavFixture(seconds: 1.0, name: "pipe\(i)"))
    }
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("mf-pipe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    return PipelineConfig(
        sourceFiles: urls, workDirectory: work, language: .english, diarize: diarize,
        template: TemplateContent(name: "T", systemPrompt: "sys", sections: ["Summary"]),
        model: "m")
}

@Test func fullRunEmitsOrderedEvents() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    var events: [PipelineEvent] = []
    for try await event in coordinator.run(try fixtureConfig(diarize: true)) {
        events.append(event)
    }
    // combined → transcribed → diarized → minutes
    var sawCombined = false, sawTranscribed = false, sawDiarized = false
    var markdown = ""
    var finalUsage: UsageStats?
    for event in events {
        switch event {
        case .combined: sawCombined = true
        case .transcribed(let segs, _):
            sawTranscribed = true
            #expect(segs.first?.text == "hello world")
        case .diarized(let segs):
            sawDiarized = true
            #expect(segs.first?.speaker == "S1")
        case .minutesDelta(let d): markdown += d
        case .minutesCompleted(let md, let usage, _):
            #expect(md == "# Minutes body")
            finalUsage = usage
        case .stageChanged: break
        }
    }
    #expect(sawCombined && sawTranscribed && sawDiarized)
    #expect(markdown == "# Minutes body")
    #expect(finalUsage?.totalTokens == 15)
}

@Test func skipsDiarizationWhenOff() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    var sawDiarized = false
    for try await event in coordinator.run(try fixtureConfig(diarize: false)) {
        if case .diarized = event { sawDiarized = true }
    }
    #expect(!sawDiarized)
}

@Test func transcriptionFailureCarriesStage() async throws {
    let engine = FakeEngine(segments: [], error: .failed("boom"))
    let coordinator = PipelineCoordinator(engine: engine, diarizer: FakeDiarizer(), provider: FakeProvider())
    do {
        for try await _ in coordinator.run(try fixtureConfig(diarize: false)) {}
        Issue.record("expected throw")
    } catch let error as PipelineError {
        #expect(error.stage == .transcribing)
    }
}

@Test func generateOnlySkipsAudioStages() async throws {
    let coordinator = PipelineCoordinator(engine: FakeEngine(), diarizer: FakeDiarizer(), provider: FakeProvider())
    let segments = [TranscriptSegment(start: 0, end: 1, text: "cached", speaker: "S1")]
    var sawCombined = false
    var markdown = ""
    for try await event in coordinator.generateOnly(try fixtureConfig(diarize: true), segments: segments, diarized: true) {
        switch event {
        case .combined: sawCombined = true
        case .minutesCompleted(let md, _, _): markdown = md
        default: break
        }
    }
    #expect(!sawCombined)
    #expect(markdown == "# Minutes body")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter Pipeline`
Expected: FAIL.

- [ ] **Step 3: Implement PipelineCoordinator.swift**

```swift
import Foundation

public enum PipelineStage: String, Sendable {
    case combining, transcribing, diarizing, generating
}

public enum PipelineEvent: Sendable {
    case stageChanged(PipelineStage)
    case combined(url: URL, duration: TimeInterval)
    case transcribed(segments: [TranscriptSegment], wallTime: TimeInterval)
    case diarized(segments: [TranscriptSegment])
    case minutesDelta(String)
    case minutesCompleted(markdown: String, usage: UsageStats, latency: TimeInterval)
}

public struct PipelineError: Error {
    public let stage: PipelineStage
    public let underlying: Error
}

public struct PipelineConfig: Sendable {
    public var sourceFiles: [URL]
    public var workDirectory: URL
    public var language: MeetingLanguage
    public var diarize: Bool
    public var template: TemplateContent
    public var speakerNames: [String: String]
    public var model: String
    public var apiKey: String?

    public init(sourceFiles: [URL], workDirectory: URL, language: MeetingLanguage,
                diarize: Bool, template: TemplateContent,
                speakerNames: [String: String] = [:], model: String, apiKey: String? = nil) {
        self.sourceFiles = sourceFiles
        self.workDirectory = workDirectory
        self.language = language
        self.diarize = diarize
        self.template = template
        self.speakerNames = speakerNames
        self.model = model
        self.apiKey = apiKey
    }
}

public struct PipelineCoordinator: Sendable {
    let engine: TranscriptionEngine
    let diarizer: Diarizer
    let provider: MinutesProvider

    public init(engine: TranscriptionEngine, diarizer: Diarizer, provider: MinutesProvider) {
        self.engine = engine
        self.diarizer = diarizer
        self.provider = provider
    }

    public func run(_ config: PipelineConfig) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // 1. Combine
                    continuation.yield(.stageChanged(.combining))
                    let combinedURL = config.workDirectory.appendingPathComponent("combined.m4a")
                    let duration: TimeInterval
                    do {
                        duration = try await AudioCombiner.combine(
                            fileURLs: config.sourceFiles, outputURL: combinedURL)
                    } catch {
                        throw PipelineError(stage: .combining, underlying: error)
                    }
                    continuation.yield(.combined(url: combinedURL, duration: duration))

                    // 2. Transcribe
                    continuation.yield(.stageChanged(.transcribing))
                    var segments: [TranscriptSegment]
                    let started = ContinuousClock.now
                    do {
                        try await engine.prepare(language: config.language)
                        segments = try await engine.transcribe(
                            fileURL: combinedURL, language: config.language, onProgress: { _ in })
                    } catch {
                        throw PipelineError(stage: .transcribing, underlying: error)
                    }
                    let wallTime = Double((ContinuousClock.now - started).components.seconds)
                    continuation.yield(.transcribed(segments: segments, wallTime: wallTime))

                    // 3. Diarize (optional)
                    if config.diarize {
                        continuation.yield(.stageChanged(.diarizing))
                        do {
                            let turns = try await diarizer.speakerTurns(fileURL: combinedURL)
                            segments = SpeakerMerger.merge(segments: segments, turns: turns)
                        } catch {
                            throw PipelineError(stage: .diarizing, underlying: error)
                        }
                        continuation.yield(.diarized(segments: segments))
                    }

                    // 4. Generate
                    try await generate(config: config, segments: segments,
                                       diarized: config.diarize, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func generateOnly(
        _ config: PipelineConfig, segments: [TranscriptSegment], diarized: Bool
    ) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await generate(config: config, segments: segments,
                                       diarized: diarized, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(
        config: PipelineConfig, segments: [TranscriptSegment], diarized: Bool,
        continuation: AsyncThrowingStream<PipelineEvent, Error>.Continuation
    ) async throws {
        continuation.yield(.stageChanged(.generating))
        let (system, user) = PromptBuilder.build(
            template: config.template, transcript: segments,
            speakerNames: config.speakerNames, diarized: diarized)
        let request = MinutesRequest(
            systemPrompt: system, userPrompt: user, model: config.model, apiKey: config.apiKey)
        let started = ContinuousClock.now
        var markdown = ""
        var usage = UsageStats(inputTokens: 0, outputTokens: 0)
        do {
            for try await event in try await provider.generate(request) {
                switch event {
                case .textDelta(let delta):
                    markdown += delta
                    continuation.yield(.minutesDelta(delta))
                case .completed(let stats):
                    usage = stats
                }
            }
        } catch {
            throw PipelineError(stage: .generating, underlying: error)
        }
        let latency = Double((ContinuousClock.now - started).components.seconds)
        continuation.yield(.minutesCompleted(markdown: markdown, usage: usage, latency: latency))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter Pipeline`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: PipelineCoordinator orchestrates combine/transcribe/diarize/generate"
```

---

### Task 15: MinutesExporter (MD / HTML / PDF / clipboard)

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Export/MinutesExporter.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/MinutesExporterTests.swift`

**Interfaces:**
- Produces:
  - `MinutesExporter.html(markdown: String, title: String) -> String` — full standalone HTML doc, print-friendly CSS inline
  - `MinutesExporter.pdf(markdown: String, title: String) async throws -> Data` (`@MainActor`, offscreen WKWebView)
  - `MinutesExporter.copyToClipboard(markdown: String, richText: Bool)` (`@MainActor`)
  - `ExportError.pdfFailed(String)`

- [ ] **Step 1: Write failing HTML tests**

`MinutesExporterTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func htmlWrapsRenderedMarkdown() {
    let html = MinutesExporter.html(markdown: "# Ata\n\n- **ponto** um", title: "Reunião 14/07")
    #expect(html.contains("<h1>Ata</h1>"))
    #expect(html.contains("<strong>ponto</strong>"))
    #expect(html.contains("<title>Reunião 14/07</title>"))
    #expect(html.lowercased().contains("<!doctype html>"))
    #expect(html.contains("@media print")) // print-friendly CSS present
}

@Test func htmlEscapesTitle() {
    let html = MinutesExporter.html(markdown: "text", title: "<script>x</script>")
    #expect(!html.contains("<script>x</script>"))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter MinutesExporter`
Expected: FAIL.

- [ ] **Step 3: Implement MinutesExporter.swift**

```swift
import Foundation
import Ink
import WebKit
import AppKit

public enum ExportError: Error {
    case pdfFailed(String)
}

public enum MinutesExporter {
    public static func html(markdown: String, title: String) -> String {
        let body = MarkdownParser().html(from: markdown)
        let safeTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(safeTitle)</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", sans-serif; max-width: 46rem;
               margin: 2rem auto; padding: 0 1rem; line-height: 1.55; color: #1d1d1f; }
        h1, h2, h3 { line-height: 1.25; }
        h2 { border-bottom: 1px solid #d2d2d7; padding-bottom: .3rem; margin-top: 2rem; }
        li { margin: .25rem 0; }
        code { background: #f5f5f7; padding: .1rem .3rem; border-radius: 4px; }
        @media print { body { margin: 0 auto; font-size: 11pt; } }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    @MainActor
    public static func pdf(markdown: String, title: String) async throws -> Data {
        let htmlDocument = html(markdown: markdown, title: title)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123)) // A4 @ 96dpi
        let navigator = NavigationWaiter()
        webView.navigationDelegate = navigator
        webView.loadHTMLString(htmlDocument, baseURL: nil)
        try await navigator.waitUntilLoaded()
        do {
            let config = WKPDFConfiguration()
            return try await webView.pdf(configuration: config)
        } catch {
            throw ExportError.pdfFailed(String(describing: error))
        }
    }

    @MainActor
    public static func copyToClipboard(markdown: String, richText: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if richText {
            let htmlDocument = html(markdown: markdown, title: "Minutes")
            if let data = htmlDocument.data(using: .utf8),
               let attributed = NSAttributedString(
                   html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil),
               let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length)) {
                pasteboard.setData(rtf, forType: .rtf)
            }
        }
        pasteboard.setString(markdown, forType: .string)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitUntilLoaded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: ExportError.pdfFailed(String(describing: error)))
        continuation = nil
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter MinutesExporter`
Expected: 2 PASS. (PDF and clipboard are verified in-app — they need a GUI session.)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: minutes exporter for HTML, PDF and clipboard"
```

---

### Task 16: BuiltinTemplates

**Files:**
- Create: `MeetingForgeCore/Sources/MeetingForgeCore/Templates/BuiltinTemplates.swift`
- Create: `MeetingForgeCore/Tests/MeetingForgeCoreTests/BuiltinTemplatesTests.swift`

**Interfaces:**
- Produces: `BuiltinTemplates.all: [BuiltinTemplate]` where `struct BuiltinTemplate { key: String, name: String, icon: String, systemPrompt: String, sections: [String] }`. Keys: `"business"`, `"it"`, `"personal"`. App seeds `MeetingTemplate` rows from these on first launch (Task 17) and "reset to default" looks up by key.

- [ ] **Step 1: Write failing test**

`BuiltinTemplatesTests.swift`:

```swift
import Testing
@testable import MeetingForgeCore

@Test func threeBuiltinsWithStableKeys() {
    let keys = BuiltinTemplates.all.map(\.key)
    #expect(keys == ["business", "it", "personal"])
    for template in BuiltinTemplates.all {
        #expect(!template.systemPrompt.isEmpty)
        #expect(!template.sections.isEmpty)
        #expect(BuiltinTemplates.template(forKey: template.key)?.name == template.name)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path MeetingForgeCore --filter Builtin`
Expected: FAIL.

- [ ] **Step 3: Implement BuiltinTemplates.swift**

```swift
import Foundation

public struct BuiltinTemplate: Sendable {
    public let key: String
    public let name: String
    public let icon: String
    public let systemPrompt: String
    public let sections: [String]
}

public enum BuiltinTemplates {
    public static func template(forKey key: String) -> BuiltinTemplate? {
        all.first { $0.key == key }
    }

    public static let all: [BuiltinTemplate] = [
        BuiltinTemplate(
            key: "business",
            name: "Business Meeting",
            icon: "briefcase",
            systemPrompt: """
            You are an experienced executive assistant writing formal meeting minutes \
            (ata de reunião). Be precise and neutral. Attribute statements to speakers \
            when speaker labels are present. Capture decisions verbatim where possible. \
            For every action point include the owner (if identifiable) and any mentioned deadline. \
            Do not invent information that is not in the transcript.
            """,
            sections: ["Summary", "Participants", "Decisions", "Action Points",
                       "Open Questions", "Next Steps"]
        ),
        BuiltinTemplate(
            key: "it",
            name: "IT / Engineering Meeting",
            icon: "laptopcomputer",
            systemPrompt: """
            You are a senior engineering manager writing minutes for a technical meeting. \
            Preserve technical terms, system names, version numbers and error messages exactly \
            as spoken. Separate decisions from open technical debates. For action points, \
            include owner and affected system/component. List anything that requires further \
            research or a spike under Research. Do not invent information that is not in the transcript.
            """,
            sections: ["Summary", "Technical Decisions", "Action Points", "Blockers & Risks",
                       "Research / Spikes", "Open Questions"]
        ),
        BuiltinTemplate(
            key: "personal",
            name: "Personal / Informal",
            icon: "person.2",
            systemPrompt: """
            You are summarizing an informal conversation or personal planning session. \
            Keep the tone light and the summary short. Focus on what was agreed, who does what, \
            and anything to remember or look up later. Do not invent information that is not in \
            the transcript.
            """,
            sections: ["Summary", "To-Do", "Ideas", "To Look Up", "Reminders"]
        ),
    ]
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path MeetingForgeCore --filter Builtin`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: builtin meeting templates (business, IT, personal)"
```

---

### Task 17: App shell — paths, container, template seeding, sidebar

**Files:**
- Create: `App/AppPaths.swift`
- Modify: `App/MeetingForgeApp.swift`
- Modify: `App/Views/ContentView.swift`
- Create: `App/Views/HistoryListView.swift`

**Interfaces:**
- Consumes: SwiftData models (Task 2), `BuiltinTemplates` (Task 16).
- Produces: `AppPaths.audioDirectory(meetingID:) -> URL`, `AppPaths.whisperModelsDirectory: URL`; a running app with sidebar sections New Meeting / History / Templates / Settings. Navigation via `enum SidebarItem`.

UI tasks have no unit tests — each ends with a build + manual launch check.

- [ ] **Step 1: Write AppPaths.swift**

```swift
import Foundation

enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingForge")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func audioDirectory(meetingID: UUID) -> URL {
        let dir = root.appendingPathComponent("audio").appendingPathComponent(meetingID.uuidString)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("source"), withIntermediateDirectories: true)
        return dir
    }

    static var whisperModelsDirectory: URL {
        root.appendingPathComponent("whisper-models")
    }
}
```

- [ ] **Step 2: Rewrite MeetingForgeApp.swift with container + seeding**

```swift
import SwiftUI
import SwiftData
import MeetingForgeCore

@main
struct MeetingForgeApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Meeting.self, Transcript.self, MinutesRun.self, MeetingTemplate.self)
            Self.seedBuiltinTemplates(context: container.mainContext)
        } catch {
            fatalError("Cannot create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    @MainActor
    static func seedBuiltinTemplates(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<MeetingTemplate>())) ?? []
        let existingKeys = Set(existing.compactMap(\.builtinKey))
        for builtin in BuiltinTemplates.all where !existingKeys.contains(builtin.key) {
            context.insert(MeetingTemplate(
                name: builtin.name, icon: builtin.icon,
                systemPrompt: builtin.systemPrompt, sections: builtin.sections,
                isBuiltin: true, builtinKey: builtin.key))
        }
        try? context.save()
    }
}
```

- [ ] **Step 3: Rewrite ContentView.swift as NavigationSplitView**

```swift
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
```

Until Tasks 18–21 exist, add temporary placeholder views at the bottom of `ContentView.swift` so it compiles; each later task deletes its placeholder:

```swift
// TEMPORARY placeholders — removed as Tasks 18-21 land their real views.
struct NewMeetingView: View { var body: some View { Text("New Meeting") } }
struct TemplateListView: View { var body: some View { Text("Templates") } }
struct SettingsView: View { var body: some View { Text("Settings") } }
```

- [ ] **Step 4: Write HistoryListView.swift**

```swift
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

// TEMPORARY placeholder — replaced in Task 19.
struct MeetingDetailView: View {
    let meeting: Meeting
    var body: some View { Text(meeting.title) }
}
```

Note: audio-folder cleanup on delete is finalized in Task 18 once meetings store their folder UUID (`Meeting` gets its audio path from `combinedAudioPath`); at this point best-effort delete is acceptable.

- [ ] **Step 5: Build + launch**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Launch the built app from DerivedData (or `open` the product); sidebar shows 4 items, History shows empty state, Templates/Settings show placeholders.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: app shell with sidebar, model container, template seeding"
```

---

### Task 18: SettingsStore + SettingsView

**Files:**
- Create: `App/ViewModels/SettingsStore.swift`
- Modify: `App/Views/ContentView.swift` (delete `SettingsView` placeholder)
- Create: `App/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `KeychainStore` (Task 13), `WhisperKitModelManager` (Task 6), `ClaudeCodeProvider.detectExecutable` (Task 11), `ModelPrice`/`CostCalculator` (Task 12), `ProviderID`, `TranscriptionEngineID`.
- Produces: `SettingsStore` (`@Observable`, `@MainActor`) — the app-wide config object later tasks read:

```swift
@Observable @MainActor final class SettingsStore {
    var engineID: TranscriptionEngineID          // persisted UserDefaults "engine"
    var whisperModel: String                     // persisted "whisper-model"
    var defaultProvider: ProviderID              // persisted "default-provider"
    var defaultModels: [ProviderID: String]      // persisted "default-model-<id>"
    var claudeExecutablePath: String?            // persisted "claude-path"; nil = auto-detect
    var priceOverrides: [String: ModelPrice]     // persisted "price-overrides" (JSON)

    func apiKey(for provider: ProviderID) -> String?
    func setAPIKey(_ key: String?, for provider: ProviderID)   // Keychain-backed
    func makeProvider(_ id: ProviderID) -> MinutesProvider
    func makeEngine() -> TranscriptionEngine
    func claudeExecutableURL() -> URL?           // explicit path or detectExecutable()
}
```

- [ ] **Step 1: Implement SettingsStore.swift**

```swift
import Foundation
import Observation
import MeetingForgeCore

@Observable @MainActor
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.funnietech.meetingforge")

    var engineID: TranscriptionEngineID {
        didSet { defaults.set(engineID.rawValue, forKey: "engine") }
    }
    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: "whisper-model") }
    }
    var defaultProvider: ProviderID {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "default-provider") }
    }
    var claudeExecutablePath: String? {
        didSet { defaults.set(claudeExecutablePath, forKey: "claude-path") }
    }
    var priceOverrides: [String: ModelPrice] {
        didSet { defaults.set(try? JSONEncoder().encode(priceOverrides), forKey: "price-overrides") }
    }

    init() {
        engineID = TranscriptionEngineID(rawValue: defaults.string(forKey: "engine") ?? "") ?? .appleSpeech
        whisperModel = defaults.string(forKey: "whisper-model") ?? "openai_whisper-base"
        defaultProvider = ProviderID(rawValue: defaults.string(forKey: "default-provider") ?? "") ?? .anthropic
        claudeExecutablePath = defaults.string(forKey: "claude-path")
        if let data = defaults.data(forKey: "price-overrides"),
           let decoded = try? JSONDecoder().decode([String: ModelPrice].self, from: data) {
            priceOverrides = decoded
        } else {
            priceOverrides = [:]
        }
    }

    func defaultModel(for provider: ProviderID) -> String? {
        defaults.string(forKey: "default-model-\(provider.rawValue)")
    }

    func setDefaultModel(_ model: String, for provider: ProviderID) {
        defaults.set(model, forKey: "default-model-\(provider.rawValue)")
    }

    func apiKey(for provider: ProviderID) -> String? {
        keychain.get(account: provider.rawValue)
    }

    func setAPIKey(_ key: String?, for provider: ProviderID) {
        if let key, !key.isEmpty {
            try? keychain.set(key, account: provider.rawValue)
        } else {
            try? keychain.delete(account: provider.rawValue)
        }
    }

    func claudeExecutableURL() -> URL? {
        if let path = claudeExecutablePath, !path.isEmpty {
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        return ClaudeCodeProvider.detectExecutable()
    }

    func makeProvider(_ id: ProviderID) -> MinutesProvider {
        switch id {
        case .openAI: OpenAIProvider()
        case .anthropic: AnthropicProvider()
        case .gemini: GeminiProvider()
        case .ollamaCloud: OllamaCloudProvider()
        case .claudeCode: ClaudeCodeProvider(executableURL: claudeExecutableURL())
        }
    }

    func makeEngine() -> TranscriptionEngine {
        switch engineID {
        case .appleSpeech: AppleSpeechEngine()
        case .whisperKit: WhisperKitEngine(
            modelName: whisperModel, modelsDirectory: AppPaths.whisperModelsDirectory)
        }
    }

    func costCalculator() -> CostCalculator {
        CostCalculator(overrides: priceOverrides)
    }
}
```

Inject one instance app-wide: in `MeetingForgeApp`, add `@State private var settings = SettingsStore()` and `.environment(settings)` on `ContentView()`.

- [ ] **Step 2: Implement SettingsView.swift (delete placeholder in ContentView.swift)**

```swift
import SwiftUI
import MeetingForgeCore

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var keys: [ProviderID: String] = [:]
    @State private var claudeStatus: String = ""
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadedModels: [String] = []

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
                }
            }

            Section("AI Providers — API Keys") {
                ForEach(ProviderID.allCases.filter(\.requiresAPIKey), id: \.self) { provider in
                    SecureField(provider.displayName, text: binding(for: provider))
                }
                Picker("Default provider", selection: $settings.defaultProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
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

            Section("Model prices (USD per 1M tokens)") {
                PriceTableEditor(overrides: $settings.priceOverrides)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            refreshModels()
            for provider in ProviderID.allCases where provider.requiresAPIKey {
                keys[provider] = settings.apiKey(for: provider) ?? ""
            }
        }
    }

    private func binding(for provider: ProviderID) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { newValue in
                keys[provider] = newValue
                settings.setAPIKey(newValue, for: provider)
            })
    }

    private func refreshModels() {
        downloadedModels = whisperManager.downloadedModels()
    }

    private func download(_ model: String) {
        downloadProgress[model] = 0
        Task {
            do {
                let manager = whisperManager
                try await manager.download(model) { fraction in
                    Task { @MainActor in downloadProgress[model] = fraction }
                }
            } catch {
                claudeStatus = "Download failed: \(error.localizedDescription)"
            }
            downloadProgress[model] = nil
            refreshModels()
        }
    }
}

struct PriceTableEditor: View {
    @Binding var overrides: [String: ModelPrice]
    @State private var newModel = ""
    @State private var newInput = ""
    @State private var newOutput = ""

    var body: some View {
        ForEach(CostCalculator.defaultPrices.keys.sorted(), id: \.self) { key in
            let price = overrides[key] ?? CostCalculator.defaultPrices[key]!
            HStack {
                Text(key)
                Spacer()
                Text("in \(price.inputPerMTok, specifier: "%.2f") / out \(price.outputPerMTok, specifier: "%.2f")")
                    .foregroundStyle(overrides[key] == nil ? .secondary : .primary)
            }.font(.caption)
        }
        HStack {
            TextField("model prefix", text: $newModel)
            TextField("in $/MTok", text: $newInput).frame(width: 80)
            TextField("out $/MTok", text: $newOutput).frame(width: 80)
            Button("Set") {
                if let input = Double(newInput), let output = Double(newOutput), !newModel.isEmpty {
                    overrides[newModel] = ModelPrice(inputPerMTok: input, outputPerMTok: output)
                    newModel = ""; newInput = ""; newOutput = ""
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build + manual check**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Launch: enter a dummy API key, relaunch app, key still there (Keychain). "Check" finds your claude CLI. Switch engine to WhisperKit → model list appears; download `openai_whisper-base` and watch progress.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: settings with API keys, engine toggle, whisper models, prices"
```

---

### Task 19: NewMeetingView + MeetingRunViewModel + RunProgressView + MeetingDetailView

**Files:**
- Create: `App/ViewModels/MeetingRunViewModel.swift`
- Modify: `App/Views/ContentView.swift` (delete `NewMeetingView` placeholder)
- Create: `App/Views/NewMeetingView.swift`
- Create: `App/Views/RunProgressView.swift`
- Modify: `App/Views/HistoryListView.swift` (delete `MeetingDetailView` placeholder)
- Create: `App/Views/MeetingDetailView.swift`

**Interfaces:**
- Consumes: `PipelineCoordinator`/`PipelineConfig`/`PipelineEvent` (Task 14), `SettingsStore` (Task 18), `ModelCatalog` (Task 12), `FluidAudioDiarizer` (Task 7), `MinutesExporter` (Task 15), SwiftData models, `AppPaths`.
- Produces: full run flow — pick files → run → live progress → saved Meeting; detail view with Minutes/Transcript/Audio/Stats tabs, export menu, speaker rename, regenerate.

- [ ] **Step 1: Implement MeetingRunViewModel.swift**

```swift
import Foundation
import Observation
import SwiftData
import MeetingForgeCore

@Observable @MainActor
final class MeetingRunViewModel {
    enum RunState: Equatable {
        case idle
        case running(stage: PipelineStage)
        case failed(stage: PipelineStage?, message: String)
        case done
    }

    var state: RunState = .idle
    var liveMarkdown = ""
    var meetingID: PersistentIdentifier?

    func start(
        title: String, files: [URL], language: MeetingLanguage, diarize: Bool,
        template: MeetingTemplate, provider: ProviderID, model: String,
        settings: SettingsStore, context: ModelContext
    ) {
        let meeting = Meeting(title: title, language: language)
        let meetingUUID = UUID()
        let audioDir = AppPaths.audioDirectory(meetingID: meetingUUID)

        // Copy sources into the meeting folder so history owns its audio.
        var copiedFiles: [URL] = []
        for file in files {
            let dest = audioDir.appendingPathComponent("source").appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: file, to: dest)
                copiedFiles.append(dest)
            } catch {
                state = .failed(stage: nil, message: "Cannot copy \(file.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }
        meeting.sourceFileNames = copiedFiles.map(\.lastPathComponent)
        meeting.status = .transcribing
        context.insert(meeting)
        try? context.save()
        meetingID = meeting.persistentModelID

        let config = PipelineConfig(
            sourceFiles: copiedFiles,
            workDirectory: audioDir,
            language: language,
            diarize: diarize,
            template: TemplateContent(
                name: template.name, systemPrompt: template.systemPrompt, sections: template.sections),
            model: model,
            apiKey: settings.apiKey(for: provider))
        let coordinator = PipelineCoordinator(
            engine: settings.makeEngine(),
            diarizer: FluidAudioDiarizer(),
            provider: settings.makeProvider(provider))
        let calculator = settings.costCalculator()

        liveMarkdown = ""
        state = .running(stage: .combining)

        Task {
            do {
                for try await event in coordinator.run(config) {
                    switch event {
                    case .stageChanged(let stage):
                        state = .running(stage: stage)
                        meeting.status = stage == .generating ? .generating : .transcribing
                    case .combined(let url, let duration):
                        meeting.combinedAudioPath = url.path
                        meeting.durationSeconds = duration
                    case .transcribed(let segments, let wallTime):
                        let transcript = Transcript(engine: settings.engineID, diarized: diarize)
                        try transcript.setSegments(segments)
                        transcript.wallTimeSeconds = wallTime
                        meeting.transcript = transcript
                    case .diarized(let segments):
                        try meeting.transcript?.setSegments(segments)
                    case .minutesDelta(let delta):
                        liveMarkdown += delta
                    case .minutesCompleted(let markdown, let usage, let latency):
                        let run = MinutesRun(
                            provider: provider, modelName: model, templateName: template.name,
                            markdown: markdown,
                            inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                            costUSD: calculator.cost(model: model, usage: usage) ?? 0,
                            latencySeconds: latency)
                        meeting.minutesRuns.append(run)
                    }
                    try? context.save()
                }
                meeting.status = .done
                try? context.save()
                state = .done
            } catch let error as PipelineError {
                meeting.status = .failed
                try? context.save()
                state = .failed(stage: error.stage, message: describe(error.underlying))
            } catch {
                meeting.status = .failed
                try? context.save()
                state = .failed(stage: nil, message: describe(error))
            }
        }
    }

    /// Regenerate minutes for an existing meeting (retry, other provider/model/template).
    func regenerate(
        meeting: Meeting, template: MeetingTemplate, provider: ProviderID, model: String,
        settings: SettingsStore, context: ModelContext
    ) {
        guard let transcript = meeting.transcript,
              let segments = try? transcript.segments() else {
            state = .failed(stage: nil, message: "No transcript stored for this meeting.")
            return
        }
        let config = PipelineConfig(
            sourceFiles: [], workDirectory: FileManager.default.temporaryDirectory,
            language: meeting.language, diarize: transcript.diarized,
            template: TemplateContent(
                name: template.name, systemPrompt: template.systemPrompt, sections: template.sections),
            speakerNames: (try? transcript.speakerNames()) ?? [:],
            model: model, apiKey: settings.apiKey(for: provider))
        let coordinator = PipelineCoordinator(
            engine: settings.makeEngine(), diarizer: FluidAudioDiarizer(),
            provider: settings.makeProvider(provider))
        let calculator = settings.costCalculator()

        liveMarkdown = ""
        state = .running(stage: .generating)
        meeting.status = .generating
        Task {
            do {
                for try await event in coordinator.generateOnly(
                    config, segments: segments, diarized: transcript.diarized) {
                    switch event {
                    case .minutesDelta(let delta): liveMarkdown += delta
                    case .minutesCompleted(let markdown, let usage, let latency):
                        let run = MinutesRun(
                            provider: provider, modelName: model, templateName: template.name,
                            markdown: markdown,
                            inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                            costUSD: calculator.cost(model: model, usage: usage) ?? 0,
                            latencySeconds: latency)
                        meeting.minutesRuns.append(run)
                    default: break
                    }
                }
                meeting.status = .done
                try? context.save()
                state = .done
            } catch {
                meeting.status = .done // transcript still valid; only this run failed
                try? context.save()
                state = .failed(stage: .generating, message: describe(error))
            }
        }
    }

    private func describe(_ error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingAPIKey(let id): return "\(id.displayName): API key missing — add it in Settings."
            case .http(let status, let message): return "HTTP \(status): \(message)"
            case .malformedResponse(let detail): return "Malformed response: \(detail)"
            case .executableNotFound(let detail): return detail
            case .cliFailure(let detail): return "Claude Code failed: \(detail)"
            }
        }
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .assetUnavailable(let detail): return "Speech assets unavailable: \(detail)"
            case .modelNotDownloaded(let model): return "Whisper model \(model) not downloaded — get it in Settings."
            case .failed(let detail): return "Transcription failed: \(detail)"
            }
        }
        return String(describing: error)
    }
}
```

- [ ] **Step 2: Implement NewMeetingView.swift (delete placeholder)**

```swift
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
                              || runViewModel.state != .idle && runViewModel.state != .done)
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
```

- [ ] **Step 3: Implement RunProgressView.swift**

```swift
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
```

- [ ] **Step 4: Implement MeetingDetailView.swift (delete placeholder in HistoryListView.swift)**

```swift
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
```

Note: `PromptBuilder.timestamp` is `internal` in Core — change its declaration to `public static func timestamp(...)` in this task so the app can use it (adjust in `PromptBuilder.swift`, no test change needed).

- [ ] **Step 5: Build + end-to-end manual run**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Launch and do a full run: add 2 short audio files, pt-BR, diarization ON, Business template, a provider you have a key for → watch stages → minutes stream in → meeting appears in History → detail shows all 4 tabs, export MD works, speaker rename persists, Regenerate creates a second run visible in Stats.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: new meeting flow, run progress, meeting detail with export and stats"
```

---

### Task 20: Template editor

**Files:**
- Modify: `App/Views/ContentView.swift` (delete `TemplateListView` placeholder)
- Create: `App/Views/TemplateListView.swift`
- Create: `App/Views/TemplateEditorView.swift`

**Interfaces:**
- Consumes: `MeetingTemplate` (Task 2), `BuiltinTemplates` (Task 16).
- Produces: template CRUD UI — create, edit, delete (custom only), reset-to-default (builtins only).

- [ ] **Step 1: Implement TemplateListView.swift**

```swift
import SwiftUI
import SwiftData
import MeetingForgeCore

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]
    @State private var editing: MeetingTemplate?

    var body: some View {
        List {
            ForEach(templates) { template in
                HStack {
                    Label(template.name, systemImage: template.icon)
                    if template.isBuiltin {
                        Text("built-in").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editing = template }
                    if template.isBuiltin {
                        Button("Reset") { reset(template) }
                    } else {
                        Button(role: .destructive) {
                            context.delete(template)
                            try? context.save()
                        } label: { Text("Delete") }
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .toolbar {
            Button {
                let template = MeetingTemplate(
                    name: "New Template", icon: "doc.text",
                    systemPrompt: "You are an expert minute-taker. Do not invent information.",
                    sections: ["Summary", "Action Points"])
                context.insert(template)
                try? context.save()
                editing = template
            } label: { Label("New Template", systemImage: "plus") }
        }
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template)
        }
    }

    private func reset(_ template: MeetingTemplate) {
        guard let key = template.builtinKey,
              let builtin = BuiltinTemplates.template(forKey: key) else { return }
        template.name = builtin.name
        template.icon = builtin.icon
        template.systemPrompt = builtin.systemPrompt
        template.sections = builtin.sections
        try? context.save()
    }
}
```

- [ ] **Step 2: Implement TemplateEditorView.swift**

```swift
import SwiftUI
import SwiftData
import MeetingForgeCore

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: MeetingTemplate
    @State private var sectionsText = ""

    var body: some View {
        Form {
            TextField("Name", text: $template.name)
            TextField("SF Symbol icon", text: $template.icon)
            Section("System prompt") {
                TextEditor(text: $template.systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
            }
            Section("Sections (one per line, in order)") {
                TextEditor(text: $sectionsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
            }
            HStack {
                Spacer()
                Button("Done") {
                    template.sections = sectionsText
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
        .onAppear { sectionsText = template.sections.joined(separator: "\n") }
    }
}
```

- [ ] **Step 3: Build + manual check**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Launch: edit Business template → change persists; Reset restores original; create custom template → appears in NewMeetingView picker; delete works, builtins have no delete.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: template list and editor with builtin reset"
```

---

### Task 21: Integration verification + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Full test suite**

Run: `swift test --package-path MeetingForgeCore`
Expected: all tests PASS.

- [ ] **Step 2: Full build**

Run: `xcodegen generate && xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: End-to-end checklist (manual, in app)**

Verify each; fix anything broken before README:

1. Two audio files, reordered → combined playback in Audio tab is in the chosen order.
2. Diarization ON with a 2-speaker recording → transcript shows S1/S2; rename → minutes regenerate uses new names.
3. Each configured provider generates minutes; Stats row shows tokens; cost non-zero for priced models; Claude Code row shows CLI-reported cost.
4. Language: pt-BR audio with Auto → Portuguese minutes.
5. Exports: MD, HTML, PDF files open correctly; both clipboard modes paste into TextEdit.
6. Kill provider mid-run (revoke key) → failure shows stage + message; Regenerate succeeds without retranscribing.
7. Engine switch to WhisperKit (model downloaded) → transcription works.

- [ ] **Step 4: Write README.md**

Content: what the app does (1 paragraph), requirements (macOS 26, Xcode 26, xcodegen, optional claude CLI), build commands (`xcodegen generate`, `xcodebuild ...`, `swift test --package-path MeetingForgeCore`), provider setup (where to get each API key, Settings screenshot placeholder), architecture pointer to `docs/superpowers/specs/2026-07-14-meetingforge-design.md`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "docs: README with build and setup instructions"
```

---

## Self-Review Notes

- **Spec coverage:** audio combine (T3), local transcription both engines (T5, T6), diarization + checkbox (T7, T19), 5 providers (T9–T11), model picker + live lists (T12, T19), usage stats + cost (T12, T14, T19 stats tab), templates editable + custom + reset (T16, T20), exports MD/HTML/PDF/clipboard (T15, T19), history with audio/transcript/runs (T2, T17, T19), pt-BR/en + auto (T2, T5, T6), retry-from-stage (regenerate without retranscribe: T14 `generateOnly`, T19), Keychain keys (T13, T18), Claude Code detection (T11, T18).
- **Deliberate simplifications (v1):** progress for WhisperKit is indeterminate; retry-from-stage is implemented as "regenerate minutes only" (transcription failures rerun the whole pipeline — audio combine is cheap); history delete does best-effort audio cleanup.
- **Type consistency check done:** `TemplateContent` vs `MeetingTemplate` conversion happens only in ViewModels; `PromptBuilder.timestamp` becomes public in T19.





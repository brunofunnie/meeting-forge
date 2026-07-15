# MeetingForge — Design Spec

**Date:** 2026-07-14 (updated post-v1.0.0 to match the shipped app)
**Status:** As built

## Overview

Native macOS app (Swift/SwiftUI, macOS 26+) that turns one or more meeting audio files into structured meeting minutes ("ata de reunião"). Audio is combined if multiple, transcribed locally (with optional speaker diarization), then sent to a user-selected AI provider and model to generate minutes from a configurable template. Results are exportable (PDF, HTML, Markdown, clipboard) and every processed meeting is kept in history with full AI usage stats.

**Languages:** Portuguese (pt-BR) and English. Transcription language selectable per run (pt-BR / en / auto-detect between the two). The minutes output language is an independent per-run choice: **Same as audio** (default), **pt-BR**, or **English** — stored on the meeting and reused when regenerating.

## Architecture

```
MeetingForge.app (SwiftUI, macOS 26)
│
├── UI Layer (SwiftUI)
│   ├── ContentView: NavigationSplitView; detail column wrapped in a
│   │   NavigationStack re-identified per sidebar selection (pops pushed
│   │   pages on section change). Owns NewMeetingFormModel so New Meeting
│   │   input and run progress survive navigation.
│   ├── Sidebar: New Meeting | History | Templates | Settings
│   ├── NewMeetingView: drop/pick audio files, reorder list, transcription
│   │   language picker, minutes-language picker, diarization checkbox,
│   │   template picker, provider + model dropdown (live catalog + custom id),
│   │   toolbar reset button (clears all fields)
│   ├── HistoryListView: rows with date+time, status, last provider/model;
│   │   per-row delete button with confirmation (removes audio folder too)
│   ├── MeetingDetailView: tabs — Minutes | Transcript | Audio | Stats;
│   │   export menu; RegenerateSheet (provider + model dropdown + template);
│   │   audio playback via AVPlayerView wrapped in NSViewRepresentable
│   │   (SwiftUI VideoPlayer crashes in tab switches on macOS 26.5)
│   ├── TemplateListView / TemplateEditorView: edit/create/reset templates
│   └── SettingsView: engine toggle, WhisperKit model manager, provider API
│       keys, default provider, Ollama-local server URL + optional key,
│       Claude Code path + detection
│
├── Core (MeetingForgeCore Swift package)
│   ├── AudioCombiner        — AVMutableComposition, N files → 1 m4a
│   │                          (atomic export: temp file + replace on success)
│   ├── TranscriptionEngine  — protocol
│   │   ├── AppleSpeechEngine    (SpeechAnalyzer/SpeechTranscriber, default;
│   │   │                         auto-detect probes first 30s then reruns)
│   │   └── WhisperKitEngine     (CoreML Whisper, model download manager)
│   ├── DiarizationService   — FluidAudio; SpeakerMerger assigns speakers by
│   │                          max time-overlap (nearest-turn fallback)
│   ├── MinutesProvider      — protocol
│   │   ├── OpenAIProvider, AnthropicProvider, GeminiProvider,
│   │   │   OllamaCloudProvider   (URLSession streaming; Ollama variant is
│   │   │   parameterized: cloud w/ Bearer auth, or local w/ configurable
│   │   │   base URL and optional key)
│   │   └── ClaudeCodeProvider    (Process → `claude -p --output-format json`;
│   │                              concurrent stdin/stdout/stderr pipe I/O,
│   │                              SIGPIPE-guarded, terminates child on cancel)
│   ├── PromptBuilder        — template prompt + section list + language rule
│   │                          (match transcript / force pt-BR / force en)
│   ├── ModelCatalog         — live model lists per provider, 24h cache
│   ├── CostCalculator       — built-in per-model price table, longest-prefix
│   │                          match; provider-reported cost wins (Claude Code)
│   ├── PipelineCoordinator  — orchestrates combine → transcribe → [diarize] → AI
│   ├── KeychainStore        — generic-password wrapper for API keys
│   └── MinutesExporter      — MD → HTML (Ink) → PDF (offscreen WKWebView),
│                              clipboard (MD/RTF)
│
├── Persistence
│   ├── SwiftData: Meeting, Transcript, MinutesRun, MeetingTemplate
│   ├── Files: ~/Library/Application Support/MeetingForge/audio/<uuid>/
│   └── Keychain: API keys per provider (service com.funnietech.meetingforge)
│
└── Packaging
    └── scripts/package.sh — Release build → ad-hoc signed .app → compressed
        DMG with /Applications symlink + Install.command (copies app, strips
        quarantine, launches). App icon from meeting-forge.png (AppIcon.icns).
```

### Transcription engines

Both engines implemented behind the `TranscriptionEngine` protocol; user switches in Settings.

- **AppleSpeechEngine (default):** Apple SpeechAnalyzer/SpeechTranscriber (macOS 26). On-device, fast, pt-BR and en built-in, zero model downloads. Auto-detect transcribes a 30-second probe clip in English, classifies with NLLanguageRecognizer (pt/en), then runs the full pass in the detected language.
- **WhisperKitEngine (opt-in):** CoreML Whisper via WhisperKit. Better accuracy on noisy/accented audio. Settings offers a model picker (base, small, large-v3, large-v3-turbo) with download manager (progress, delete). A run with WhisperKit selected but no model downloaded fails with a prompt to download first.

### AI providers and model selection

Six providers behind the `MinutesProvider` protocol:

| Provider | Transport | Usage stats source |
|---|---|---|
| OpenAI | HTTPS, streaming | `usage` in response |
| Anthropic (Claude API) | HTTPS, streaming | `usage` in response |
| Google AI Studio (Gemini) | HTTPS, streaming | `usageMetadata` in response |
| Ollama Cloud | HTTPS, streaming | `prompt_eval_count` / `eval_count` |
| Ollama (local) | HTTP to configurable server URL (default `http://localhost:11434`), optional Bearer key | `prompt_eval_count` / `eval_count` |
| Claude Code CLI | subprocess `claude -p --output-format json` | `usage` + `total_cost_usd` in JSON output |

**Model selection:** provider picker + model dropdown in NewMeetingView *and* in the RegenerateSheet; default provider/model pair set in Settings. Model lists fetched live and cached for 24h (refresh button): OpenAI `GET /v1/models`, Anthropic `GET /v1/models`, Gemini `models.list`, Ollama `GET /api/tags`. Claude Code uses `--model` with an alias list (sonnet / opus / haiku). NewMeetingView also accepts a free-text custom model ID.

**Availability:** providers without an API key (or a missing `claude` CLI) render disabled in the pickers with a hint; run/regenerate buttons are guarded on availability. Ollama (local) is always selectable — reachability errors surface at run time.

**Mid-stream errors:** OpenAI/Anthropic error events inside a 200 stream abort the run with the server message instead of silently saving truncated minutes.

**Cost:** built-in per-model price table (longest-prefix match; no editor UI). Claude Code uses its reported `total_cost_usd` directly; local Ollama costs 0.

## Data model (SwiftData)

- **Meeting:** title, date, source audio filenames (ordered, index-prefixed on copy to avoid same-name collisions), combined audio path, duration, transcription language, minutes output language (`minutesLanguageRaw`, optional for migration), status (pending / transcribing / generating / done / failed), `audioFolderUUID` (locates the meeting's audio folder for cleanup on delete).
- **Transcript:** full text, segments `[{start, end, text, speaker?}]`, engine used, diarization flag, transcription wall time. Speaker display names editable (defaults "S1", "S2", …).
- **MinutesRun** (many per Meeting): markdown output, provider, model name, template name, input tokens, output tokens, total tokens, estimated cost (USD), latency, timestamp. Reruns append new MinutesRun records — old runs preserved for comparison and stats history.
- **MeetingTemplate:** name, icon, system prompt, ordered section list (e.g. Summary, Action Points, Questions, Research, Decisions), builtin flag + stable builtin key. Three builtins ship (Business, IT, Personal); builtins are editable with reset-to-default; users can create unlimited custom templates.

## Pipeline (data flow)

1. **Ingest:** user drops/picks N audio files → copied to `audio/<meeting-uuid>/source/` with index-prefixed names (preserves order, avoids clashes). User reorders in UI before starting.
2. **Combine:** `AVMutableComposition` appends tracks in user order → export `combined.m4a` (AAC) atomically (temp file, moved into place on success). Single files also go through export so downstream always reads one m4a.
3. **Transcribe:** selected engine returns timed segments; stage progress shown in UI.
4. **Diarize** (checkbox on): FluidAudio produces speaker turns `[{start, end, speakerID}]`; SpeakerMerger assigns each transcript segment the speaker with maximum time overlap (nearest turn as fallback). Speakers renamable afterward; renames propagate to minutes regeneration.
5. **Generate minutes:** prompt = template system prompt + section list + language rule (from the meeting's minutes-language choice) + transcript (speaker-labeled when diarized). Response streams into the UI. Usage stats captured per provider (table above).
6. **Persist:** each stage's output saved as it completes. A failure at stage 5 keeps the transcript; Regenerate produces new minutes without retranscribing (different provider/model/template allowed), reusing the stored minutes language and speaker renames.

## Export

- Minutes stored as Markdown (source of truth).
- **Markdown:** save file as-is.
- **HTML:** Markdown → HTML via Ink with a print-friendly CSS template.
- **PDF:** offscreen `WKWebView` loads the HTML → `createPDF` (navigation-failure and process-termination handlers prevent hangs).
- **Clipboard:** plain Markdown or rich text (NSAttributedString from HTML).

## Error handling

- Pipeline stages return typed errors carrying the failing stage; the UI shows stage + message. Regenerate retries minutes without restarting the pipeline.
- Provider errors: HTTP status + API error message shown verbatim, including mid-stream error events.
- Claude Code CLI not installed: detected in Settings (`which claude` + common paths, path overridable); provider disabled in pickers with hint. Subprocess I/O is deadlock-safe (concurrent pipe draining, SIGPIPE ignored on stdin) and the child is terminated if the run is cancelled.
- WhisperKit model missing: run fails with a prompt to download in Settings; download errors shown in the Transcription section.
- API keys stored in Keychain, persisted on submit/leave (not per keystroke); a provider without a key is disabled with a hint in the picker.
- History delete asks for confirmation and removes the meeting's audio folder via its stored UUID.

## Packaging & distribution

- `scripts/package.sh [version]`: xcodegen → Release xcodebuild → ad-hoc codesign (identity overridable via `CODESIGN_IDENTITY`) → compressed DMG containing the app, an /Applications symlink, and `Install.command` (copies the app, strips the quarantine flag, launches).
- App icon generated from `meeting-forge.png` into `AppIcon.icns` (`CFBundleIconFile`).
- Releases published on GitHub with the DMG attached.

## Testing

- **Core unit tests (66):** AudioCombiner (fixture wavs, atomic-export contract), speaker merge logic, prompt building incl. output-language rules, provider response parsing and mid-stream errors (mock transport fixtures), local-Ollama keyless path, Claude Code subprocess incl. pipe-deadlock regression (stub executable), model catalog caching, cost calculation, Keychain round-trip, pipeline orchestration with fakes (stage order, failure attribution), HTML export.
- **Transcription engines:** thin adapters over vendor APIs; env-gated smoke test (`MF_SMOKE_AUDIO`) plus manual verification.
- **UI:** manual testing.

## Out of scope (v1)

- Live/recording capture (file input only).
- Languages beyond pt-BR and English.
- iCloud sync / multi-device.
- Editing the transcript text itself (speaker renames only).
- Notarized distribution (ad-hoc signing + Install.command instead).

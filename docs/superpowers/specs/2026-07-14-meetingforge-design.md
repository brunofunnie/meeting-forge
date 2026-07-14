# MeetingForge — Design Spec

**Date:** 2026-07-14
**Status:** Approved design, pending implementation plan

## Overview

Native macOS app (Swift/SwiftUI, macOS 26+) that turns one or more meeting audio files into structured meeting minutes ("ata de reunião"). Audio is combined if multiple, transcribed locally (with optional speaker diarization), then sent to a user-selected AI provider and model to generate minutes from a configurable template. Results are exportable (PDF, HTML, Markdown, clipboard) and every processed meeting is kept in history with full AI usage stats.

**Languages supported (v1):** Portuguese (pt-BR) and English. Transcription language selectable per run (pt-BR / en / auto-detect between the two); minutes are generated in the same language as the transcript.

## Architecture

```
MeetingForge.app (SwiftUI, macOS 26)
│
├── UI Layer (SwiftUI)
│   ├── Sidebar: History | New Meeting | Templates | Settings
│   ├── NewMeetingView: drop/pick audio files, reorder list, language picker,
│   │   diarization checkbox, template picker, provider + model picker
│   ├── MeetingDetailView: tabs — Minutes | Transcript | Audio | Stats
│   ├── TemplateEditorView: edit/create templates
│   └── SettingsView: engine toggle, WhisperKit model manager,
│       provider API keys, default provider/model, price table
│
├── Core (framework-agnostic Swift)
│   ├── AudioCombiner        — AVMutableComposition, N files → 1 m4a
│   ├── TranscriptionEngine  — protocol
│   │   ├── AppleSpeechEngine    (SpeechAnalyzer/SpeechTranscriber, default)
│   │   └── WhisperKitEngine     (CoreML Whisper, model download manager)
│   ├── DiarizationService   — FluidAudio; merges speaker turns with transcript
│   ├── MinutesProvider      — protocol
│   │   ├── OpenAIProvider, AnthropicProvider, GeminiProvider,
│   │   │   OllamaCloudProvider   (URLSession, streaming)
│   │   └── ClaudeCodeProvider    (Process → `claude -p --output-format json`)
│   ├── PipelineCoordinator  — orchestrates combine → transcribe → [diarize] → AI
│   └── Exporter             — MD → HTML → PDF (WKWebView), clipboard (MD/RTF)
│
└── Persistence
    ├── SwiftData: Meeting, Transcript, MinutesRun, MeetingTemplate
    ├── Files: ~/Library/Application Support/MeetingForge/audio/<uuid>/
    └── Keychain: API keys per provider
```

### Transcription engines

Both engines implemented behind the `TranscriptionEngine` protocol; user switches in Settings.

- **AppleSpeechEngine (default):** Apple SpeechAnalyzer/SpeechTranscriber (macOS 26). On-device, fast, pt-BR and en built-in, zero model downloads.
- **WhisperKitEngine (opt-in):** CoreML Whisper via WhisperKit. Better accuracy on noisy/accented audio. Settings offers model picker (e.g. base, small, medium, large-v3-turbo) with download manager (progress, delete). A run with WhisperKit selected but no model downloaded prompts download first.

### AI providers and model selection

Five providers behind the `MinutesProvider` protocol:

| Provider | Transport | Usage stats source |
|---|---|---|
| OpenAI | HTTPS, streaming | `usage` in response |
| Anthropic (Claude API) | HTTPS, streaming | `usage` in response |
| Google AI Studio (Gemini) | HTTPS, streaming | `usageMetadata` in response |
| Ollama Cloud | HTTPS, streaming | `prompt_eval_count` / `eval_count` |
| Claude Code CLI | subprocess `claude -p --output-format json` | `usage` + `total_cost_usd` in JSON output |

**Model selection:** provider picker + model dropdown in NewMeetingView; default provider/model pair set in Settings. Model lists fetched live and cached (refresh button): OpenAI `GET /v1/models`, Anthropic `GET /v1/models`, Gemini `models.list`, Ollama `GET /api/tags`. Claude Code uses `--model` with an alias list (sonnet / opus / haiku). A free-text custom model ID is always allowed for every provider.

**Cost:** built-in price table per model (editable in Settings) × token counts. Claude Code uses its reported `total_cost_usd` directly.

## Data model (SwiftData)

- **Meeting:** title, date, source audio filenames (ordered), combined audio path, duration, language, status (pending / transcribing / generating / done / failed).
- **Transcript:** full text, segments `[{start, end, text, speaker?}]`, engine used, diarization flag, transcription wall time. Speaker display names editable (defaults "Speaker 1", "Speaker 2", …).
- **MinutesRun** (many per Meeting): markdown output, provider, model name, template reference, input tokens, output tokens, total tokens, estimated cost (USD), latency, timestamp. Reruns append new MinutesRun records — old runs preserved for comparison and stats history.
- **MeetingTemplate:** name, icon, system prompt, ordered section list (e.g. Summary, Action Points, Questions, Research, Decisions), output-language rule, builtin flag. Three builtins ship (Business, IT, Personal); builtins are editable with reset-to-default; users can create unlimited custom templates.

## Pipeline (data flow)

1. **Ingest:** user drops/picks N audio files → copied to `audio/<meeting-uuid>/source/`. User reorders in UI. Any CoreAudio-decodable format accepted (mp3, m4a, wav, aiff, caf, …); undecodable files rejected at drop time with a format message.
2. **Combine** (N > 1): `AVMutableComposition` appends tracks in user order → export `combined.m4a` (AAC). Single file skips this step.
3. **Transcribe:** selected engine emits an async stream of timed segments → live progress in UI.
4. **Diarize** (checkbox on): FluidAudio produces speaker turns `[{start, end, speakerID}]`. Merge: each transcript segment is assigned the speaker with maximum time overlap. User can rename speakers afterward; renames propagate to minutes regeneration.
5. **Generate minutes:** prompt = template system prompt + output-language rule + transcript (speaker-labeled when diarized). Response streams into the UI. Usage stats captured per provider (table above).
6. **Persist:** each stage's output saved as it completes. A failure at stage 5 keeps the transcript; retry regenerates minutes only. Rerunning with a different provider/model/template creates a new MinutesRun without retranscribing.

## Export

- Minutes stored as Markdown (source of truth).
- **Markdown:** save file as-is.
- **HTML:** Markdown → HTML via swift-markdown with a print-friendly CSS template.
- **PDF:** offscreen `WKWebView` loads the HTML → `createPDF`.
- **Clipboard:** plain Markdown or rich text (NSAttributedString from HTML).

## Error handling

- Each pipeline stage returns typed errors surfaced in the UI with retry-from-stage; the whole pipeline never restarts from scratch.
- Provider errors: HTTP status + API error message shown verbatim; rate limits suggest retry.
- Claude Code CLI not installed: detected in Settings (`which claude`); provider disabled with install hint.
- WhisperKit model missing: prompt to download before running.
- API keys stored in Keychain; a provider without a key is disabled with a hint in the picker.

## Testing

- **Core unit tests:** AudioCombiner (fixture wavs), segment/speaker merge logic, prompt building, provider response parsing (recorded JSON fixtures), cost calculation, Markdown→HTML export.
- **Providers:** mocked URLSession; ClaudeCodeProvider tested against a stub executable.
- **Transcription engines:** thin adapters over vendor APIs; smoke-tested manually (model-dependent, not CI-viable).
- **UI:** manual testing plus targeted ViewModel tests.

## Out of scope (v1)

- Live/recording capture (file input only).
- Languages beyond pt-BR and English.
- iCloud sync / multi-device.
- Editing the transcript text itself (speaker renames only).

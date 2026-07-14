# MeetingForge

MeetingForge is a native macOS app that turns one or more meeting audio files into structured meeting minutes ("ata de reunião"). Drop in your audio, it combines multiple files into one, transcribes it locally with optional speaker diarization, then sends the transcript to an AI provider of your choice to generate minutes from a configurable template. Minutes can be exported as Markdown, HTML, or PDF, copied to the clipboard, and every processed meeting is kept in history with full transcript, audio, and per-run usage stats.

## Requirements

- macOS 26
- Xcode 26
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Optional: the [`claude` CLI](https://docs.anthropic.com/en/docs/claude-code) installed and on `PATH`, if you want to use the Claude Code provider (no API key needed for that one — see below)

## Build

```bash
xcodegen generate
xcodebuild -project MeetingForge.xcodeproj -scheme MeetingForge -destination 'platform=macOS' build
```

Run the core test suite (business logic, providers, pipeline — no Xcode project needed):

```bash
swift test --package-path MeetingForgeCore
```

## Provider setup

MeetingForge supports five AI providers for minutes generation. Enter API keys in the app's **Settings** screen — they're stored in the macOS Keychain, never in plain files or SwiftData.

| Provider | Get an API key at | Notes |
|---|---|---|
| OpenAI | https://platform.openai.com | API key from your account's API keys page |
| Anthropic (Claude API) | https://console.anthropic.com | API key from the console |
| Google AI Studio (Gemini) | https://aistudio.google.com | Generate a key from AI Studio |
| Ollama Cloud | https://ollama.com (API key page in your account) | Cloud-hosted models, not a local Ollama install |
| Claude Code CLI | — | No API key. Requires the `claude` CLI installed locally; MeetingForge detects it and shells out to it. Cost is whatever the CLI itself reports. |

Settings also lets you set a default provider/model pair, edit the per-model price table used for cost estimates, and refresh each provider's live model list.

## Transcription

- **Apple SpeechAnalyzer / SpeechTranscriber** (default): on-device, built into macOS 26, no model downloads, supports pt-BR and en out of the box.
- **WhisperKit** (optional): CoreML Whisper, switchable in Settings. Better accuracy on noisy or accented audio. Models (base, small, large-v3, large-v3-turbo) are downloaded on demand from the Settings model manager; a run won't start on WhisperKit until a model is downloaded.

Transcription language is selectable per run: Portuguese (pt-BR), English, or auto-detect between the two. Minutes are generated in the same language as the transcript.

## Diarization (optional)

Turn on the diarization checkbox when starting a meeting to get speaker-labeled transcripts (S1, S2, ...) via FluidAudio. Models download automatically on first use. Speakers can be renamed after the fact; regenerating minutes picks up the new names without re-transcribing.

## Exports

Minutes are stored as Markdown and can be exported as:

- Markdown (`.md`)
- HTML (styled, print-friendly)
- PDF (rendered from the HTML)
- Clipboard, as plain Markdown or rich text

## Architecture

See [`docs/superpowers/specs/2026-07-14-meetingforge-design.md`](docs/superpowers/specs/2026-07-14-meetingforge-design.md) for the full design: module layout, data model, pipeline stages, provider details, and error handling.

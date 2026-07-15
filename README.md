<p align="center">
  <img src="meeting-forge.png" alt="MeetingForge" width="160">
</p>

# MeetingForge

MeetingForge is a native macOS app that turns one or more meeting audio files into structured meeting minutes ("ata de reunião"). Drop in your audio, it combines multiple files into one, transcribes it locally with optional speaker diarization, then sends the transcript to an AI provider of your choice to generate minutes from a configurable template — in the transcript's language or a language you pick. Minutes can be exported as Markdown, HTML, or PDF, copied to the clipboard, and every processed meeting is kept in history with full transcript, audio, and per-run usage stats (tokens, cost, latency).

## Download & install

Grab the latest DMG from the [Releases page](../../releases). The app is ad-hoc signed (not notarized), so macOS quarantines it on download. Two ways to install:

- **Easiest:** open the DMG and double-click **Install.command** — it copies the app to /Applications, removes the quarantine flag, and launches it. (macOS may warn about the script itself the first time: right-click → Open.)
- **Manual:** drag MeetingForge.app to Applications, then run:

  ```bash
  xattr -d com.apple.quarantine /Applications/MeetingForge.app
  ```

A DMG can't run anything automatically when you drag the app — that's Gatekeeper working as intended; only notarization with a paid Developer ID removes the prompt entirely.

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

## Package (.app + DMG)

```bash
scripts/package.sh              # → dist/MeetingForge.app + dist/MeetingForge-<version>.dmg
scripts/package.sh 1.0.0        # explicit version label for the DMG filename
```

Signing is ad-hoc by default (fine on your own Mac). To distribute to other Macs, set a real identity and notarize afterwards:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package.sh 1.0.0
```

## Provider setup

MeetingForge supports six AI providers for minutes generation. Enter API keys in the app's **Settings** screen — they're stored in the macOS Keychain, never in plain files or SwiftData.

| Provider | Get an API key at | Notes |
|---|---|---|
| OpenAI | https://platform.openai.com | API key from your account's API keys page |
| Anthropic (Claude API) | https://console.anthropic.com | API key from the console |
| Google AI Studio (Gemini) | https://aistudio.google.com | Generate a key from AI Studio |
| Ollama Cloud | https://ollama.com (API key page in your account) | Cloud-hosted models, not a local Ollama install |
| Ollama (local) | — | No API key by default. Talks to your local Ollama install; server URL (default `http://localhost:11434`) and an optional key are configurable in Settings. |
| Claude Code CLI | — | No API key. Requires the `claude` CLI installed locally; MeetingForge detects it and shells out to it. Cost is whatever the CLI itself reports. |

Providers without a key (or the missing `claude` CLI) show up disabled in the pickers with a hint. Settings also lets you set a default provider/model pair and refresh each provider's live model list — the same dropdown is available when regenerating minutes for an existing meeting. Cost estimates use a built-in per-model price table (Claude Code reports its own cost directly; local Ollama is free).

## Transcription

- **Apple SpeechAnalyzer / SpeechTranscriber** (default): on-device, built into macOS 26, no model downloads, supports pt-BR and en out of the box.
- **WhisperKit** (optional): CoreML Whisper, switchable in Settings. Better accuracy on noisy or accented audio. Models (base, small, large-v3, large-v3-turbo) are downloaded on demand from the Settings model manager; a run won't start on WhisperKit until a model is downloaded.

Transcription language is selectable per run: Portuguese (pt-BR), English, or auto-detect between the two. The minutes output language is a separate choice — "Same as audio" (default), Portuguese (BR), or English — so an English meeting can produce uma ata em português, and vice versa. Regenerating reuses the meeting's stored choice.

## Diarization (optional)

Turn on the diarization checkbox when starting a meeting to get speaker-labeled transcripts (S1, S2, ...) via FluidAudio. Models download automatically on first use. Speakers can be renamed after the fact; regenerating minutes picks up the new names without re-transcribing.

## History

Every processed meeting is stored with its audio, transcript, and all minutes runs. From History you can reopen a meeting (Minutes / Transcript / Audio / Stats tabs), regenerate minutes with a different provider, model, or template without re-transcribing, and delete a meeting (with confirmation — removes the record and its audio files). Rows show date, time, status, and the last provider/model used.

## Exports

Minutes are stored as Markdown and can be exported as:

- Markdown (`.md`)
- HTML (styled, print-friendly)
- PDF (rendered from the HTML)
- Clipboard, as plain Markdown or rich text

## Architecture

See [`docs/superpowers/specs/2026-07-14-meetingforge-design.md`](docs/superpowers/specs/2026-07-14-meetingforge-design.md) for the full design: module layout, data model, pipeline stages, provider details, and error handling.

# VerbVox

Hold a hotkey, talk, let go. VerbVox types what you said into whatever app is in front.

VerbVox is a menu-bar dictation app for macOS. It records your microphone while you hold a global hotkey, transcribes the audio, cleans up the text, and pastes it into the frontmost app. Speech-to-text runs on your own Mac with a bundled build of [whisper.cpp](https://github.com/ggml-org/whisper.cpp), so it works right after install: no server to set up, no account, no API key. AI cleanup and text-to-speech are optional.

## What it does

- Two hold-to-talk hotkeys: **⌃⌥** pastes plain dictation, **⌃⌘** pastes an AI-cleaned version. Both are configurable.
- Transcribes on your Mac with a built-in whisper.cpp engine. The first launch downloads a speech model; after that, dictation needs no network.
- Times the engine on your Mac and moves to a larger, more accurate model by itself when the Mac is fast enough.
- Can use a whisper server you run yourself instead, on the same Mac or on your local network. If that server stops answering for 15 seconds, the built-in engine takes over until it is back.
- Other speech-to-text options: Apple's on-device transcriber (macOS 26+), Groq, OpenAI, or Deepgram.
- Strips filler words ("uh", "um"), applies your custom dictionary, and can filter profanity.
- Optional AI cleanup through Groq, OpenAI, or Gemini, with prompts you can edit. It detects the kind of app you're in (code editor, chat, email) and adjusts the cleanup.
- Voice commands like "translate this to Spanish" and "hey ai, …" questions, with optional spoken answers.
- Puts your clipboard back after it pastes.
- Lives in the menu bar. There is no Dock icon.
- Keeps a history of dictations, words-per-minute stats, and optional per-app logs.

## How the built-in engine works

`app/build.sh` compiles whisper.cpp v1.9.5 into a static `whisper-server` with the Metal shaders embedded and puts it inside `VerbVox.app`. When VerbVox starts, it runs that server on a random port on `127.0.0.1`, waits for it to answer, and transcribes an 8.5-second warm-up clip to prove the model works.

On first launch it downloads **Small (compressed)**, about 190 MB. Then it times the warm-up clip. If your Mac is fast enough, it downloads **Large v3 Turbo (compressed)**, about 575 MB, in the background, tests it the same way, and switches. Every download is checked against a pinned size and SHA-256, and an interrupted download resumes where it stopped. Models live in `~/Library/Application Support/VerbVox/models`. To pick a model yourself instead of Automatic, use **Settings → Recording**.

If the engine crashes, VerbVox restarts it. If a download fails, it tries again.

## Privacy

With the built-in engine (the default), your audio never leaves your Mac. The network is only used to download the speech models from Hugging Face.

Cloud providers are opt-in. If you pick Groq, OpenAI, or Deepgram for speech-to-text, your recording goes to that service. AI cleanup, "hey ai" questions, and translation send the text to the AI provider you picked, and OpenAI or Deepgram text-to-speech sends the text it reads aloud. There is no telemetry or analytics.

API keys you enter in Settings are stored unencrypted in a local SQLite database (`~/Library/Application Support/VerbVox/transcribe_app.db`), readable by your user account.

## Requirements

- An Apple silicon Mac (M1 or later) with macOS 14 or later
- To build: Xcode 15 or the Command Line Tools (Swift 5.9+), `git`, and `cmake` (`brew install cmake`)

## Build and run

```bash
git clone https://github.com/alesloa/verbvox.git
cd verbvox/app
./build.sh                 # release build + bundled speech engine → ../dist/VerbVox.app
open ../dist/VerbVox.app
```

The first `build.sh` also clones and compiles whisper.cpp into `app/.cache/`. Later builds reuse it. There are no prebuilt releases yet.

To install into `/Applications`:

```bash
./install.sh               # build + copy to /Applications/VerbVox.app
./reload.sh                # rebuild, reinstall, and relaunch the running app
```

A waveform icon appears in the menu bar.

### Signing it as yourself

`build.sh` signs the app ad-hoc by default. A **stable** signing identity keeps macOS from dropping the Accessibility and Input Monitoring grants on every rebuild. To use one, create `app/codesign.local.sh` (git-ignored):

```bash
SIGN_ID="Apple Development: Your Name (TEAMID)"   # find yours: security find-identity -v -p codesigning
```

### Permissions

Grant these to VerbVox in **System Settings → Privacy & Security**:

- **Microphone** to record your voice.
- **Accessibility** and **Input Monitoring** for the global hotkeys and the ⌘V paste.
- **Speech Recognition**, only if you use Apple's on-device transcriber.
- **Local Network**, only if you use your own whisper server on another machine.

If the hotkeys don't fire, Accessibility is almost always the missing one.

## Settings

Home (status and stats) · Recording (speech source, model, features, text-to-speech, logging) · Whisper (start, stop, and model control for a whisper server you run yourself, through a `whisperctl` panel) · AI & Prompts · Dictionary · Profanity · Hotkeys · History · Logs · About.

Settings, the dictionary, the profanity list, prompts, and history all live in the local database above.

## Development

```bash
cd app
swift build
swift test                                                       # unit tests
VERBVOX_LIVE_ENGINE=1 swift test --filter BuiltinWhisperTests    # real engine; downloads ~820 MB into /tmp
```

The Swift engine started as a port of an earlier Python script (`transcribe_cli.py`), so many comments name the Python function a piece of code replaced, and the text-cleanup tests check parity with that script's output.

## Optional: public whisper endpoint

`whisper-proxy/` is a small **token-gated reverse proxy** for exposing a whisper server on the public internet (whisper.cpp's server ships with no auth). It's optional and independent of the app. See [`whisper-proxy/README.md`](whisper-proxy/README.md).

## Stack

| Concern | Choice |
|---|---|
| App | Swift 5.9, SwiftUI + AppKit, menu bar only |
| Audio | AVFoundation, encoded to 16 kHz mono WAV |
| Hotkeys and paste | `NSEvent` global monitor, clipboard + synthetic ⌘V |
| Speech-to-text | bundled whisper.cpp `whisper-server` (Metal), or Apple on-device, Groq, OpenAI, Deepgram |
| AI cleanup (optional) | Groq, OpenAI, Gemini |
| Text-to-speech | `AVSpeechSynthesizer`, OpenAI, Deepgram |
| Storage | SQLite (system `libsqlite3`) |

## Repository layout

- `app/` — the Swift package (the VerbVox app + `VerbVoxCore` library + tests) and its build scripts.
- `whisper-proxy/` — optional public token gate for a whisper server.

## Project status

Dictation with the built-in engine, the cloud providers, AI cleanup, and text-to-speech are built and covered by unit tests. The built-in engine also has live tests that download real models and run the real server. VerbVox runs on Apple silicon only, because the bundled engine is built for arm64. There is no notarized release yet, so for now you build it yourself.

## License

MIT. See [LICENSE](LICENSE). Bundled and downloaded third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

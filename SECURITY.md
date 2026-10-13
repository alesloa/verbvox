# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately through GitHub:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** (GitHub private security advisories).

This keeps the report private until a fix is available. You'll get a response
through the advisory thread.

When reporting, please include:

- A description of the issue and its impact.
- Steps to reproduce (a proof of concept if you have one).
- The version / commit you tested against and your macOS version.

## Scope

VerbVox is a menu-bar app with Accessibility and Input Monitoring access: it
listens for global hotkeys and pastes text into the frontmost app. Useful things
to look at:

- The built-in speech engine (`app/Sources/VerbVoxCore/Backend/BuiltinWhisper.swift`).
  It runs the bundled `whisper-server` on a random free port bound to `127.0.0.1`
  and should never be reachable off localhost.
- Model downloads (`app/Sources/VerbVoxCore/Backend/WhisperModels.swift`). Each
  file is checked against a pinned size and SHA-256 before it is used.
- The paste path (`app/Sources/VerbVoxCore/Output/Paster.swift`), which writes to
  the clipboard and posts a synthetic ⌘V.
- `whisper-proxy/`, an optional token gate for exposing your own whisper server.

API keys you enter in Settings are stored unencrypted in the local SQLite
database under `~/Library/Application Support/VerbVox/`, readable by your user
account. That is a known design choice, not a vulnerability.

## Supported versions

This project is pre-1.0. Security fixes are made against the latest `main`.

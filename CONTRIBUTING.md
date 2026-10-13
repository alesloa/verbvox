# Contributing

Thanks for your interest in improving this project.

## Getting set up

You'll need an Apple silicon Mac with macOS 14 or later, Swift 5.9+ (Xcode 15 or
the Command Line Tools), and `cmake` for the built-in speech engine
(`brew install cmake`).

```bash
cd app
swift build
./build.sh    # release build + bundled whisper-server → ../dist/VerbVox.app
```

## Before opening a pull request

Run the checks locally:

```bash
cd app
swift test                                                   # unit tests
VERBVOX_LIVE_ENGINE=1 swift test --filter BuiltinWhisperTests  # real engine; downloads ~820 MB
```

Please keep PRs focused — one logical change per PR is much easier to review.

## Style

- Swift + SwiftUI/AppKit. Match the existing formatting and naming in the files you touch.
- Add an XCTest next to any logic change (`app/Tests/VerbVoxCoreTests/`).
- No telemetry, no analytics, no bundled API keys or secrets.

## Reporting bugs

Open an issue with steps to reproduce, your macOS version, and the app version/commit.
For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a
public issue.

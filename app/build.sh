#!/bin/bash
# Build "VerbVox.app" (release, native) into ../dist/VerbVox.app
set -e

cd "$(dirname "$0")"
APP_DIR="../dist/VerbVox.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Preparing the speech engine"
./scripts/whisper-engine.sh
ENGINE=".cache/whisper-engine/macos-arm64"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling app bundle"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/VerbVox" "$CONTENTS/MacOS/VerbVox"
# The built-in speech engine: whisper-server runs from Contents/MacOS, and the
# warm-up clip times it on each start.
cp "$ENGINE/whisper-server" "$CONTENTS/MacOS/whisper-server"
cp "$ENGINE/LICENSE-whisper.cpp.txt" "$CONTENTS/Resources/LICENSE-whisper.cpp.txt"
cp "Resources/warmup.wav" "$CONTENTS/Resources/warmup.wav"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Code signing.
# A STABLE identity (not ad-hoc) keeps the bundle's designated requirement
# constant across rebuilds, so macOS preserves the Accessibility / Input
# Monitoring grants instead of treating each build as a brand-new app.
#
# To sign with your own identity, create app/codesign.local.sh (gitignored):
#     SIGN_ID="Apple Development: Your Name (TEAMID)"
# Find yours with:  security find-identity -v -p codesigning
# Without it, we fall back to ad-hoc signing — the app still runs, but macOS
# re-prompts for Accessibility / Input Monitoring after each rebuild.
SIGN_ID=""
[ -f "codesign.local.sh" ] && source "codesign.local.sh"

if [ -n "$SIGN_ID" ]; then
  echo "==> Code signing: $SIGN_ID"
  codesign --force --sign "$SIGN_ID" "$CONTENTS/MacOS/whisper-server"
  codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
  echo "==> Code signing: ad-hoc (set SIGN_ID in app/codesign.local.sh for a stable identity)"
  codesign --force --sign - "$CONTENTS/MacOS/whisper-server"
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
echo "==> Designated requirement:"
codesign -d -r- "$APP_DIR" 2>&1 | grep -i "designated" || true

echo "==> Done: $(cd ../dist && pwd)/VerbVox.app"

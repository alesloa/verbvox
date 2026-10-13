#!/bin/bash
# Build + install "VerbVox.app" (native) to /Applications.
# Re-run this script whenever you want to rebuild + update the install.
set -e

cd "$(dirname "$0")"
APP_NAME="VerbVox"
SRC="../dist/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# Fresh release build + code sign (produces "$SRC").
./build.sh

echo "==> Installing to $DEST"
ditto "$SRC" "$DEST"

echo "==> Installed: $DEST"
echo
echo "First launch: grant these to \"$APP_NAME\" in"
echo "System Settings > Privacy & Security, then relaunch it:"
echo "   - Microphone"
echo "   - Accessibility"
echo "   - Input Monitoring"
echo "   - Local Network"

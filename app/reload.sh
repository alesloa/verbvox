#!/bin/bash
# One-shot dev reload: rebuild + reinstall "VerbVox" to /Applications,
# then quit the running instance and relaunch the fresh build.
set -e

cd "$(dirname "$0")"

# Build release + sign + ditto into /Applications/VerbVox.app
./install.sh

echo "==> Restarting VerbVox"
osascript -e 'quit app "VerbVox"' 2>/dev/null || true
sleep 1
open "/Applications/VerbVox.app"
echo "==> Relaunched fresh build."

#!/bin/bash
# Prepares the speech engine that ships inside VerbVox.app: a static whisper-server
# built from a pinned whisper.cpp commit, with the Metal shaders embedded so the
# binary needs nothing but macOS itself.
# Output: app/.cache/whisper-engine/macos-arm64/ (build.sh copies it into the bundle).
# Needs: git, cmake, and the Xcode command line tools.
set -euo pipefail

cd "$(dirname "$0")/.."
CACHE="$PWD/.cache"

# Pinned inputs. Changing any of them changes the cache key and rebuilds the engine.
# Same whisper.cpp release as VerbVox for Windows.
WHISPER_TAG="v1.9.5"
WHISPER_COMMIT="d1be6fde11ac6e0407606b4e42fe72d34add8037"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"
DEPLOYMENT_TARGET="14.0"   # matches Package.swift's .macOS(.v14)
RECIPE=1
KEY="macos-arm64|whisper.cpp-$WHISPER_COMMIT|macos-$DEPLOYMENT_TARGET|recipe-$RECIPE"

OUTPUT="$CACHE/whisper-engine/macos-arm64"
MANIFEST="$OUTPUT/engine.json"

# Every Mach-O dependency must come with macOS, so the engine runs on a Mac that
# has never seen Homebrew or a compiler.
check_engine() {
  local binary="$1/whisper-server"
  [ -x "$binary" ] || { echo "error: $binary is missing" >&2; exit 1; }
  local foreign
  foreign=$(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' || true)
  if [ -n "$foreign" ]; then
    echo "error: whisper-server links libraries that macOS does not ship:" >&2
    echo "$foreign" >&2
    exit 1
  fi
  if ! lipo -archs "$binary" | grep -qw arm64; then
    echo "error: whisper-server is not built for arm64" >&2
    exit 1
  fi
}

if [ "${1:-}" != "--force" ] && [ -f "$MANIFEST" ] && grep -qF "\"key\": \"$KEY\"" "$MANIFEST"; then
  # A cached engine is checked again on every build, so a stricter check also covers engines built before it.
  check_engine "$OUTPUT"
  echo "Speech engine is up to date: $OUTPUT"
  exit 0
fi

command -v cmake >/dev/null || { echo "error: building the speech engine needs cmake (brew install cmake)" >&2; exit 1; }
command -v git >/dev/null || { echo "error: git is required to fetch whisper.cpp" >&2; exit 1; }

SOURCE="$CACHE/whisper.cpp/$WHISPER_COMMIT"
if [ ! -d "$SOURCE/.git" ]; then
  mkdir -p "$SOURCE"
  git -C "$SOURCE" init -q
  git -C "$SOURCE" remote add origin "$WHISPER_REPO"
fi
if [ "$(git -C "$SOURCE" rev-parse --verify -q HEAD || true)" != "$WHISPER_COMMIT" ]; then
  echo "Fetching whisper.cpp $WHISPER_TAG ($WHISPER_COMMIT)"
  git -C "$SOURCE" fetch -q --depth 1 origin "$WHISPER_COMMIT"
  git -C "$SOURCE" checkout -q --force FETCH_HEAD
fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$WHISPER_COMMIT" ] || { echo "error: whisper.cpp checkout is not at $WHISPER_COMMIT" >&2; exit 1; }

BUILD="$CACHE/whisper.cpp/build-macos-arm64"
echo "Building whisper-server (static, Metal embedded)"
# GGML_NATIVE=OFF keeps the binary on the Apple-silicon baseline instead of this
# Mac's CPU, so it also runs on an M1.
cmake -S "$SOURCE" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=ON -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_SDL2=OFF -DWHISPER_FFMPEG=OFF -DWHISPER_CURL=OFF >/dev/null
cmake --build "$BUILD" --config Release --target whisper-server --parallel

STAGE="$OUTPUT.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BUILD/bin/whisper-server" "$STAGE/whisper-server"
cp "$SOURCE/LICENSE" "$STAGE/LICENSE-whisper.cpp.txt"
check_engine "$STAGE"

# --help exits before touching a model, so it proves the binary loads on this macOS.
if ! "$STAGE/whisper-server" --help 2>&1 | grep -q -- '--port'; then
  echo "error: whisper-server did not start from the staged folder" >&2
  exit 1
fi

SHA=$(shasum -a 256 "$STAGE/whisper-server" | awk '{print $1}')
cat > "$STAGE/engine.json" <<EOF
{
  "key": "$KEY",
  "whisperCpp": { "tag": "$WHISPER_TAG", "commit": "$WHISPER_COMMIT" },
  "gpu": "Metal (embedded library)",
  "whisperServerSha256": "$SHA"
}
EOF
rm -rf "$OUTPUT"
mv "$STAGE" "$OUTPUT"
echo "Speech engine is ready: $OUTPUT"

#!/usr/bin/env bash
# Launch the token-gated whisper proxy. Loads the gate token from secret.env.
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f secret.env ]]; then
  echo "secret.env missing — create it with WHISPER_PROXY_TOKEN=… (see README)." >&2
  exit 1
fi
set -a; . ./secret.env; set +a
exec python3 whisper_proxy.py

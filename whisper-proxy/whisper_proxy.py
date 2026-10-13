"""Token-gated reverse proxy in front of whisper.cpp's whisper-server.

Public traffic reaches this proxy through a Cloudflare Zero Trust tunnel pointed
at http://localhost:<port>. A request must carry the secret query token
(e.g. ?somos=<token>) or it gets a flat 401 — no login, no cookie, just the URL
secret. Valid requests are forwarded verbatim to the local whisper-server,
including multipart audio uploads.

Config (all via env — see secret.env):
  WHISPER_PROXY_TOKEN     required; requests without the matching token get 401
  WHISPER_PROXY_PARAM     query-param name carrying the token (default: somos)
  WHISPER_PROXY_UPSTREAM  whisper-server base URL (default http://127.0.0.1:8080)
  WHISPER_PROXY_HOST      bind host (default 127.0.0.1)
  WHISPER_PROXY_PORT      bind port (default 8088)
"""
import hmac
import os

import requests
from flask import Flask, Response, request


def _load_secret_env():
    """Load secret.env sitting next to this script into the environment, without
    overriding anything already set. Lets the VerbVox app launch the proxy
    directly (`python whisper_proxy.py`) without going through run.sh."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret.env")
    if not os.path.exists(path):
        return
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


_load_secret_env()

PARAM = os.environ.get("WHISPER_PROXY_PARAM", "somos")
UPSTREAM = os.environ.get("WHISPER_PROXY_UPSTREAM", "http://127.0.0.1:8080").rstrip("/")

# Hop-by-hop headers must not be forwarded (RFC 7230 §6.1); Host/Content-Length
# are rebuilt by requests for the upstream call.
_HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


def _token_ok(provided):
    """Constant-time check of the URL secret. An unset secret denies everything,
    so a misconfigured proxy fails closed rather than open."""
    secret = os.environ.get("WHISPER_PROXY_TOKEN", "")
    return bool(secret) and provided is not None and hmac.compare_digest(provided, secret)


def create_app():
    app = Flask(__name__)

    @app.route("/", defaults={"path": ""},
               methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
    @app.route("/<path:path>",
               methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
    def gate(path):
        if not _token_ok(request.args.get(PARAM)):
            return Response("Unauthorized\n", status=401, mimetype="text/plain")

        # Forward everything except the secret token itself.
        params = {k: v for k, v in request.args.items(multi=True) if k != PARAM}
        fwd_headers = {k: v for k, v in request.headers.items()
                       if k.lower() not in _HOP_BY_HOP}
        upstream = requests.request(
            method=request.method,
            url=f"{UPSTREAM}/{path}",
            params=params,
            headers=fwd_headers,
            data=request.get_data(),
            allow_redirects=False,
            timeout=600,
        )
        resp_headers = [(k, v) for k, v in upstream.headers.items()
                        if k.lower() not in _HOP_BY_HOP]
        return Response(upstream.content, status=upstream.status_code, headers=resp_headers)

    return app


if __name__ == "__main__":
    if not os.environ.get("WHISPER_PROXY_TOKEN"):
        raise SystemExit(
            "WHISPER_PROXY_TOKEN not set — refusing to start (would 401 everything). "
            "Source secret.env first: `set -a && . ./secret.env && set +a`."
        )
    create_app().run(
        host=os.environ.get("WHISPER_PROXY_HOST", "127.0.0.1"),
        port=int(os.environ.get("WHISPER_PROXY_PORT", "8088")),
        threaded=True,
    )

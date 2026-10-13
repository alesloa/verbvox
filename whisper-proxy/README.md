# whisper-proxy — public token gate for whisper-server

`whisper-server` (whisper.cpp's HTTP server) has **no authentication and no TLS**. This proxy
puts a secret-token gate in front of it so it can be exposed publicly without a login screen.

```
Internet ──TLS──▶ reverse tunnel / CDN ──▶ whisper-proxy (127.0.0.1:8088)
                                               │  checks ?somos=<token>
                                               ▼
                                     whisper-server (127.0.0.1:8080)
```

- A request must carry the secret query token, e.g. `…/inference?somos=<token>`.
- Anything missing or wrong gets a flat **`401 Unauthorized`** — no cookie, no login.
- Valid requests are forwarded verbatim (including multipart audio uploads); the token is
  stripped before forwarding.

**This is a ~40 MB doorman, not a second server. It loads NO model.** It forwards to the one
`whisper-server` on `:8080`, so there is always exactly one model in RAM.

## The secret token

The live token lives **only** in `secret.env` (git-ignored — never commit it). Generate one:

```bash
python3 -c "import secrets; print('WHISPER_PROXY_TOKEN=' + secrets.token_urlsafe(32))"
# paste the line into whisper-proxy/secret.env, then restart the proxy
```

## Running

```bash
cd whisper-proxy
./run.sh           # loads secret.env, serves on 127.0.0.1:8088
```

Requires `flask` + `requests`. `whisper-server` must be running on `127.0.0.1:8080`.

Tests:

```bash
python3 -m unittest test_whisper_proxy -v
```

## Public endpoint (once a tunnel is up)

```bash
curl "https://<your-host>/inference?somos=<token>" \
  -F file=@clip.wav -F response_format=json
```

Replace `<your-host>` with your public hostname and `<token>` with the value from `secret.env`.

## Exposing it (example: Cloudflare Tunnel)

Point a tunnel's hostname at the local proxy. `~/.cloudflared/config.yml`:

```yaml
tunnel: <tunnel-id>
credentials-file: ~/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: <your-host>
    service: http://localhost:8088
  - service: http_status:404
```

The tunnel/CDN terminates TLS; the `?somos=` token is the only access control, so don't layer a
second login (e.g. Cloudflare Access) on top of it.

## Config (env, via secret.env)

| Var | Default | Meaning |
|---|---|---|
| `WHISPER_PROXY_TOKEN` | — (required) | The URL secret. Unset = denies everything. |
| `WHISPER_PROXY_PARAM` | `somos` | Query-param name carrying the token. |
| `WHISPER_PROXY_UPSTREAM` | `http://127.0.0.1:8080` | whisper-server base URL. |
| `WHISPER_PROXY_HOST` | `127.0.0.1` | Proxy bind host. |
| `WHISPER_PROXY_PORT` | `8088` | Proxy bind port (point the tunnel here). |

## Notes

- The proxy holds no model; it only forwards to the single `whisper-server`. Exposing the server
  publicly does not add a second model to RAM.
- Start the proxy alongside `whisper-server` (whichever way you run that server); stop it when you
  no longer want the endpoint reachable.

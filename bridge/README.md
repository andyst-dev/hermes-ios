# Hermes Mobile Bridge

Standalone FastAPI bridge that lets the [Hermes Companion iOS app](https://github.com/andyst-dev/hermes-ios) drive a stock Hermes Agent install — **no patched core, no plugins, no fork**.

The bridge talks to two official Hermes surfaces:

1. **`hermes-acp`** (Agent Client Protocol server, ships with Hermes) — live chat streaming and dangerous-command approvals via the official `session/prompt` + `session/request_permission` protocol that Zed/VS Code use.
2. **`hermes dashboard`** (web admin server, ships with Hermes) — sessions, files, and model picker through its official REST API.

The phone only ever talks to this bridge (`/api/mobile/*`), so the iOS app is not coupled to Hermes internals.

## Why this exists

The original mobile bridge (in the `feat/mobile-api-bridge` branch of the hermes-agent fork) required patching `cli.py` and `web_server.py` — it only worked on that fork. This version achieves the same feature set against **unmodified upstream Hermes**, so anyone with a stock install can run it.

## Requirements

- Hermes Agent installed with the ACP extra (`cd ~/.hermes/hermes-agent && uv pip install -e '.[acp]'`)
- Python 3.11+ with `fastapi`, `uvicorn`, `httpx`, `agent-client-protocol`

## Quick start

```bash
# 1. Start the official Hermes dashboard (sessions/files/models backend)
hermes dashboard --host 127.0.0.1 --port 8765 --no-open

# 2. Start the bridge
export HERMES_DASHBOARD_SESSION_TOKEN="<dashboard-session-token>"
python -m hermes_mobile_bridge.main --host 127.0.0.1 --port 8766

# 3. Point the iOS app at http://127.0.0.1:8766
```

The bridge spawns `hermes-acp` itself and forwards:

- `POST /api/mobile/chat` → SSE stream of `delta` events, then `transcript` + `done`
- dangerous tool calls → SSE `approval` event; `POST /api/mobile/approvals/{id}/reply` writes the verdict back over ACP `request_permission`
- sessions/files/models → proxied from the dashboard REST API

## Layout

```text
hermes_mobile_bridge/
├── main.py          # FastAPI app + /api/mobile/* routes
├── acp_client.py    # ACP engine: spawn hermes-acp, sessions, streaming, permissions
├── dashboard.py     # Dashboard REST proxy (sessions, files, models)
└── models.py        # Mobile API schemas
```

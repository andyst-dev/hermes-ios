# Hermes Companion for iOS

Native SwiftUI companion app for [Hermes Agent](https://github.com/NousResearch/hermes-agent). The desktop/server instance keeps the real agent, tools, files, sessions, memory, and approvals; the iPhone/iPad app is a remote interface on top of the Hermes mobile API bridge.

## Status

Working remote client, not a mock. The app connects over HTTP to the Hermes dashboard mobile bridge, streams chat responses live, and routes dangerous-command approvals from the desktop to the phone.

## What works

- **QR pairing** — scan the desktop pairing code once; the returned token lives in Keychain (`/api/mobile/pairing` + `/api/mobile/pair`). Manual host/profile/token is tucked under Advanced connection.
- **Live streaming chat** — send a prompt and watch tokens stream via SSE (`POST /api/mobile/chat`, `Accept: text/event-stream`), then the authoritative transcript.
- **Command approvals** — when a desktop tool run is flagged dangerous (`curl | bash`, hardline patterns), the phone shows an approval card with the exact command and the security-scan reason. Approve once / deny; the verdict is written back to the desktop subprocess. Timeout or disconnect fails closed to deny.
- **Sessions** — real session list from the desktop DB, pull-to-refresh, search, source filters, pin/unpin + archive via swipe.
- **Model picker** — lists only the user's authenticated providers (never the full catalog), switches the active model.
- **Photo attachments** — pick from the photo library or from desktop-managed files; images upload to the bridge and reach the agent as `--image` inputs.
- **Desktop files** — browse and preview text files managed by the desktop policy (sensitive paths hidden).
- **Command palette** — new chat, continue last task, stop running turn, privacy mode, refresh.
- **Inspector (per conversation)** — session metadata, tools actually used in this conversation, rename/archive.
- **Markdown rendering** — code blocks, inline code, and monospace commands render properly in chat.

## Architecture

```text
hermes-ios
├── HermesCompanion       # SwiftUI app
│   ├── App               # SwiftUI entry point
│   ├── Core
│   │   ├── Models        # Stable client-side contracts
│   │   ├── Networking    # HermesTransport protocol + HTTP SSE transport + mock
│   │   └── State         # AppStore orchestration
│   ├── DesignSystem      # Ember theme (#160800 / #ffd8b0 / #d97316), brand typography
│   └── Features          # Connect, Sessions, Chat, Settings
├── plugin/               # Dashboard plugin (installs into stock Hermes)
│   ├── plugin.yaml
│   └── dashboard/
│       ├── manifest.json
│       └── plugin_api.py # 17 mobile routes, ACP engine, dashboard proxy
├── bridge/               # Standalone backend bridge (same code as plugin, dev server)
│   ├── hermes_mobile_bridge/  # main.py (routes), acp_client.py (ACP), dashboard.py (proxy)
│   └── tests/            # fake hermes-acp stdio server + mocked dashboard (19 tests)
└── docs/                 # Mobile API contract
```

- `HermesTransport` protocol keeps the app testable: production `HTTPHermesTransport`, `MockHermesTransport` for tests and demo launches (`HERMES_DEMO_CONNECTED=1`).
- The app never executes shell commands locally and never stores provider secrets. The phone asks the desktop to act.
- **No patched Hermes anywhere.** The backend is a dashboard plugin (`plugin/`) that talks to stock Hermes over its official surfaces: `hermes-acp` (Agent Client Protocol — the same one Zed/VS Code use) for live streaming + dangerous-command approvals, and the dashboard REST API for sessions/files/models.
- Mobile API contract: [`docs/mobile-api-contract.md`](docs/mobile-api-contract.md).
- Visual proof of a dangerous-command approval card rendered in the app: [`docs/approval-card-ui.png`](docs/approval-card-ui.png) (real run — `rm -rf` flagged, phone asked, verdict applied).

## Build & run

```bash
xcodegen generate
xcodebuild -scheme HermesCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the backend — **install the plugin** (requires a stock Hermes install with the ACP extra):

```bash
# 1. Install + enable the Hermes Mobile plugin (ships in this repo under plugin/)
hermes plugins install andyst-dev/hermes-ios/plugin --enable

# 2. Start the official Hermes dashboard — the plugin loads with it
hermes dashboard --host 127.0.0.1 --port 8765 --no-open
```

The plugin mounts the mobile API at `/api/plugins/hermes-mobile/*` inside the
dashboard process — no separate server. For development, the standalone bridge
also ships under `bridge/` (same code, run as its own server on port 8766):

```bash
cd bridge
python -m venv .venv && .venv/bin/pip install -e ".[dev]"
export HERMES_DASHBOARD_SESSION_TOKEN="$(cat /tmp/hermes-dev-token.txt)"
export HERMES_MOBILE_PROVIDER=deepseek HERMES_MOBILE_MODEL=deepseek-v4-flash  # optional
.venv/bin/python -m hermes_mobile_bridge.main --host 127.0.0.1 --port 8766
```

Simulator launch with an injected token (development only — the value never leaves Keychain in normal use):

```bash
SIMCTL_CHILD_HERMES_DASHBOARD_SESSION_TOKEN="$(cat /tmp/hermes-dev-token.txt)" \
SIMCTL_CHILD_HERMES_MOBILE_BASE_URL="http://127.0.0.1:8766" \
xcrun simctl launch <UDID> dev.hermes.companion
```

The `127.0.0.1:8766` bridge URL is the app's connection target; a physical iPhone needs LAN/Tailscale reachability plus pairing.

## Tests

```bash
# iOS app
xcodegen generate
xcodebuild -scheme HermesCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Backend (deterministic: fake hermes-acp stdio server + mocked dashboard)
cd bridge && .venv/bin/python -m pytest tests/ -q
```

iOS unit tests cover the SSE parser (deltas, transcripts, approval events, comment/empty frames), the store approval flow (publish + clear), session mutations against a stateful mock, and the JSON contract. Backend tests cover the ACP engine (streaming, approval once/deny/fail-closed, cancel), the standalone route contract, and the **dashboard plugin contract** (route set under `/api/plugins/hermes-mobile`, iOS JSON shapes: session status enum, message/model/tool-call fields, Z-suffixed dates, base64 file content).

## Privacy rules

- No Hermes provider secrets are stored on-device.
- Pairing tokens live in Keychain only.
- Screenshots use privacy mode; no local paths, personal names, tokens, or raw auth logs.

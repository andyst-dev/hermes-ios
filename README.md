# Hermes Companion for iOS

Native SwiftUI companion app for [Hermes Agent](https://github.com/NousResearch/hermes-agent). The desktop/server instance keeps the real agent, tools, files, sessions, memory, and approvals; the iPhone/iPad app is a remote interface on top of the Hermes mobile API bridge.

## Status

Working remote client, not a mock. The app connects over HTTP to the Hermes dashboard mobile bridge, streams chat responses live, and routes dangerous-command approvals from the desktop to the phone.

## What works

- **QR pairing** — scan the desktop pairing code once; the returned token lives in Keychain (`/api/mobile/pairing` + `/api/mobile/pair`). Manual host/profile/token is tucked under Advanced connection.
- **Live streaming chat** — send a prompt and watch tokens stream via SSE (`POST /api/mobile/chat`, `Accept: text/event-stream`), then the authoritative transcript.
- **Collapsible Thinking block** — the agent's reasoning streams on a dedicated `thinking` SSE event (ACP `agent_thought_chunk`, never mixed into the answer) and renders in a collapsible pane, desktop parity. Persisted reasoning survives reloads.
- **Command approvals** — when a desktop tool run is flagged dangerous (`curl | bash`, hardline patterns), the phone shows an approval card with the exact command and the security-scan reason. Approve once / deny; the verdict is written back to the desktop subprocess. Timeout or disconnect fails closed to deny.
- **Sessions** — real session list from the desktop DB, pull-to-refresh, search, source filters (Desktop / CLI / Mobile / Telegram sections), pin/unpin + archive via swipe. ACP-created sessions read as "Mobile"; a turn that lands in a freshly minted session (unresumable conversation) is followed automatically so replies never vanish.
- **Model picker** — lists only the user's authenticated providers (never the full catalog), switches the active model.
- **Photo attachments** — pick from the photo library or from desktop-managed files; images upload to the bridge and reach the agent as `--image` inputs.
- **Desktop files** — browse and preview text files managed by the desktop policy (sensitive paths hidden).
- **Command palette** — new chat, continue last task, stop running turn, privacy mode, refresh.
- **Remote tunnel (no VPN, no Tailscale)** — `POST /tunnel/start` opens an outbound HTTPS tunnel (cloudflared quick tunnel, no account; ngrok fallback) and the pairing QR embeds the public URL, so a real iPhone can pair from anywhere. `GET /tunnel/status` / `POST /tunnel/stop` manage it — and Settings has a **Remote access** section to start/stop it straight from the phone and copy the public URL. The tunnel points at a plugin-owned reverse proxy that rewrites the Host header back to loopback (and maps `/api/mobile/*` onto the plugin mount point), so the core Host-header guard (DNS-rebinding defence) never sees the public hostname — **no core patch needed**. The session token still protects every route.
- **Cron jobs** — browse the gateway's scheduled jobs, expand a job for its prompt, delivery target and recent runs, then pause/resume, run now or remove it straight from Settings → Cron jobs.
- **Alerts without APNs** — a Background App Refresh task polls `/notifications/pending` (approvals waiting for a phone verdict, cron runs that just finished) and fires local notifications; approvals are also surfaced in-app right after connecting. No Apple Developer paid account, no APNs key. Note: iOS schedules background refreshes opportunistically, so this is alerting within minutes, not instant push.
- **Skills & memory** — Settings → Skills & memory lists the desktop's skills (tap one for its full SKILL.md), reads the agent's persistent memory and user profile, and appends new entries straight from the phone.
- **Voice input** — tap the mic in the composer and speak; dictation runs on-device (SFSpeechRecognizer) and lands in the composer as typed text. No backend change, works offline.
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
│   ├── DesignSystem      # Ember theme (#0d0400 / #ffd8b0 / #d97316), brand typography
│   └── Features          # Connect, Sessions, Chat, Settings
├── plugin/               # Dashboard plugin (installs into stock Hermes)
│   ├── plugin.yaml
│   └── dashboard/
│       ├── manifest.json
│       └── plugin_api.py # 35 mobile routes, ACP engine, dashboard proxy, remote tunnel, cron, alerts, skills/memory
├── bridge/               # Standalone backend bridge (same code as plugin, dev server)
│   ├── hermes_mobile_bridge/  # main.py (routes), acp_client.py (ACP), dashboard.py (proxy)
│   └── tests/            # fake hermes-acp stdio server + mocked dashboard (39 tests)
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

For remote pairing (out of LAN), the tunnel needs one binary — cloudflared
recommended, no account needed:

```bash
brew install cloudflared   # or: brew install ngrok
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

The `127.0.0.1:8766` bridge URL is the app's connection target; a physical iPhone pairs over the LAN (`scripts/lan-dashboard.sh` puts the Mac's IP in the QR) or from anywhere via the remote tunnel (`POST /tunnel/start` — no VPN, no Tailscale, nothing to install on the phone).

## Tests

```bash
# iOS app
xcodegen generate
xcodebuild -scheme HermesCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Backend (deterministic: fake hermes-acp stdio server + mocked dashboard)
cd bridge && .venv/bin/python -m pytest tests/ -q
```

iOS unit tests cover the SSE parser (deltas, thinking, transcripts, approval events, comment/empty frames), the store approval flow (publish + clear), session mutations against a stateful mock, and the JSON contract. Backend tests cover the ACP engine (streaming, thinking vs delta separation, approval once/deny/fail-closed, cancel, session resume/adoption, stale-turn cancellation), the standalone route contract, the **dashboard plugin contract** (route set under `/api/plugins/hermes-mobile`, iOS JSON shapes: session status enum, message/model/tool-call fields, Z-suffixed dates, base64 file content), and the **remote tunnel** (start/stop/status lifecycle, missing-binary fail-closed, pairing QR preferring the public URL, and the reverse proxy's Host-header rewrite proven end-to-end).

## Privacy rules

- No Hermes provider secrets are stored on-device.
- Pairing tokens live in Keychain only.
- Screenshots use privacy mode; no local paths, personal names, tokens, or raw auth logs.

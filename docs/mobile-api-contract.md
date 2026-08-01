# Hermes Mobile API Contract Draft

This draft is the narrow client/server boundary for Hermes Companion. The iOS app stays a thin remote UI; the desktop/server Hermes instance owns tools, files, approvals, model secrets, sessions, and execution. The first read-only endpoints are mirrored by the Hermes dashboard backend under `/api/mobile/*`.

## Transport

- Base URL: user-paired desktop/server Hermes URL.
- Auth: dashboard session token for the first bridge (`X-Hermes-Session-Token` or `Authorization: Bearer ...`); later QR pairing should mint a mobile-scoped token stored in iOS Keychain.
- Streaming: WebSocket preferred for chat turns; HTTP polling acceptable for session metadata.
- Privacy: responses should support redacted display names/paths for public screenshot mode.

## Endpoints

### `GET /api/mobile/health`

Returns host availability and API compatibility.

```json
{
  "ok": true,
  "hostName": "Desktop Hermes",
  "profile": "default",
  "apiVersion": 1
}
```

### `GET /api/mobile/sessions`

Returns the session list sorted by most recent activity.

```json
[
  {
    "id": "session-id",
    "title": "Hermes iOS Companion",
    "subtitle": "repo · running",
    "updatedAt": "2026-08-01T14:00:00Z",
    "status": "running"
  }
]
```

### `GET /api/mobile/sessions/{sessionID}/messages`

Returns messages for one session, including compact tool cards.

### `GET /api/mobile/capabilities`

Returns desktop state for the mobile inspector without making the chat surface noisy.

```json
{
  "models": [],
  "profiles": [],
  "files": [],
  "jobs": [],
  "approvals": [],
  "tools": []
}
```

### `POST /api/mobile/chat`

Starts or continues a turn.

```json
{
  "sessionID": "session-id",
  "text": "Continue",
  "attachments": []
}
```

### `WS /api/mobile/chat/stream/{turnID}`

Streams message and tool-call deltas.

### `POST /api/mobile/sessions/{sessionID}/stop`

Requests cancellation of the active turn.

## Pairing flow

1. Desktop Hermes shows QR with one-time pairing URL.
2. iOS scans QR and exchanges pairing code for a revocable mobile token.
3. Token is stored in Keychain.
4. Desktop can revoke paired devices.

## Non-goals for iOS

- No local shell execution.
- No provider secrets in the app.
- No direct filesystem mutation from iOS; all actions go through Hermes approvals/tool policy.

# Hermes Companion for iOS

Native SwiftUI companion app for Hermes Agent. The desktop/server instance keeps the real agent, tools, files, sessions, memory, and approvals; the iPhone/iPad app is a polished remote interface.

## Status

`v0.1` prototype: buildable SwiftUI app with mock transport and an API-ready architecture.

## Product direction

- iPhone-first chat surface with the Hermes Desktop Ember palette (orange on black)
- iPad split layout inspired by Hermes Desktop
- bundled Hermes desktop logo and Collapse display font for brand parity
- session list, streaming chat, tool-call cards, composer, and settings
- future QR pairing with a revocable token stored in Keychain
- future HTTP/WebSocket transport to the Hermes dashboard/mobile API

## Architecture

```text
HermesCompanion
├── App                 # SwiftUI entry point
├── Core
│   ├── Models          # Stable client-side contracts
│   ├── Networking      # HermesTransport protocol + mock/API skeletons
│   └── State           # AppStore orchestration
├── DesignSystem        # Ember theme, brand typography, desktop-style panels
└── Features            # Connect, Sessions, Chat, Settings
```

## Build

```bash
xcodegen generate
xcodebuild -scheme HermesCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

## Backend contract

The first mobile API draft lives in [`docs/mobile-api-contract.md`](docs/mobile-api-contract.md). It keeps iOS as a remote client: Hermes on the desktop/server owns tools, filesystem access, approvals, and model credentials.

## Privacy rules

- The iOS app should never store Hermes provider secrets.
- Pairing tokens should live in Keychain once real pairing is wired.
- Public screenshots should use privacy mode and avoid local paths, personal names, tokens, OAuth codes, or raw auth logs.
- The phone asks the desktop/server Hermes to act; it does not execute shell commands locally.

## Next milestones

1. Define the Hermes mobile API contract (`/api/mobile/health`, sessions, messages, stop, streaming send).
2. Add QR pairing and Keychain token storage.
3. Replace `MockHermesTransport` with a WebSocket/HTTP transport.
4. Add attachments, voice input, approval notifications, and Live Activities.

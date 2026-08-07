#!/usr/bin/env bash
# LAN dashboard launcher for hermes-ios real-device pairing — NO Tailscale needed.
# Same Wi-Fi: the iPhone scans the QR (or types the URL manually) and connects
# straight to the Mac. The QR embeds HERMES_MOBILE_PUBLIC_URL so the phone gets
# the reachable address instead of 127.0.0.1.
#
# Usage:  ./lan-dashboard.sh [port]        (default 8765)
set -euo pipefail

PORT="${1:-8765}"
HERMES_AGENT="${HERMES_AGENT_DIR:-/Users/andy/hermes-agent}"
VENV_PY="$HERMES_AGENT/.venv/bin/python"

# 1. Detect the Mac's LAN IP (Wi-Fi en0/en1, then Ethernet en2+)
LAN_IP=""
for iface in en0 en1 en2; do
  LAN_IP="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  [ -n "$LAN_IP" ] && break
done
if [ -z "$LAN_IP" ]; then
  echo "✗ No LAN IP found — are you connected to Wi-Fi/Ethernet?" >&2
  exit 1
fi

echo "→ Mac LAN IP : $LAN_IP"
echo "→ Dashboard  : http://0.0.0.0:$PORT (all interfaces)"
echo "→ QR embeds  : http://$LAN_IP:$PORT"

# 2. macOS firewall hint (only if the iPhone cannot connect)
echo "→ If it fails: System Settings › Network › Firewall › allow incoming for python/node on port $PORT"
echo "→ iPhone prompt: grant the 'Local Network' permission to Hermes."

# 3. Launch the dashboard bound to all interfaces with the reachable URL
export HERMES_MOBILE_PUBLIC_URL="http://$LAN_IP:$PORT"
if [ -z "${HERMES_DASHBOARD_SESSION_TOKEN:-}" ] && [ -f /tmp/hermes-dev-token.txt ]; then
  export HERMES_DASHBOARD_SESSION_TOKEN="$(cat /tmp/hermes-dev-token.txt)"
fi
cd "$HERMES_AGENT"
exec "$VENV_PY" -m hermes_cli.main dashboard --host 0.0.0.0 --port "$PORT" --no-open --skip-build

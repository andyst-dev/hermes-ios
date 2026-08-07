"""Route-level tests for the mobile API contract, with a mocked dashboard.

The ACP engine is faked at the FastAPI layer (routes call engine methods we
stub), so these tests verify the HTTP contract without spawning subprocesses.
The real ACP engine itself is covered by test_acp_client.py against the fake
hermes-acp stdio server.
"""

from __future__ import annotations

import json
import os
import sys

import httpx
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from hermes_mobile_bridge import main as bridge_main  # noqa: E402
from hermes_mobile_bridge.dashboard import DashboardClient  # noqa: E402


class FakeEngine:
    """Stands in for ACPExtEngine at the route layer."""

    def __init__(self) -> None:
        self._session_map = {}
        self._active_hermes_session = None
        self.cancelled: list[str] = []
        self.resolved: list[tuple[str, str]] = []

    async def new_session(self, hermes_session_id=None):
        hid = hermes_session_id or "20260805_fake_new"
        self._session_map[hid] = "acp-uuid-1"
        self._active_hermes_session = hid
        return hid

    async def resume_session(self, hermes_session_id):
        if hermes_session_id not in self._session_map:
            self._session_map[hermes_session_id] = "acp-uuid-2"
        self._active_hermes_session = hermes_session_id
        return hermes_session_id

    async def cancel_active_turn(self):
        self.cancelled_turns = getattr(self, "cancelled_turns", 0) + 1

    def subscribe(self, hermes_session_id):
        import asyncio

        return asyncio.Queue()

    def unsubscribe(self, hermes_session_id):
        pass

    async def prompt(self, hermes_session_id, text):
        return {}

    async def cancel(self, hermes_session_id):
        self.cancelled.append(hermes_session_id)

    def resolve_approval(self, approval_id, verdict):
        self.resolved.append((approval_id, verdict))
        return approval_id != "nope"


@pytest.fixture
def client(monkeypatch):
    bridge_main._reset_runtime_for_tests()
    engine = FakeEngine()
    bridge_main._engine = engine  # type: ignore[assignment]

    # Fake dashboard over httpx MockTransport.
    def fake_handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/health":
            return httpx.Response(200, json={"ok": True, "version": "0.19.1"})
        if request.url.path == "/api/sessions":
            return httpx.Response(
                200,
                json={
                    "sessions": [
                        {
                            "id": "20260805_real",
                            "title": "Session réelle",
                            "source": "telegram",
                            "profile": "default",
                            "model": "deepseek-v4-flash",
                            "message_count": 12,
                            "pinned": False,
                            "is_active": True,
                            "updated_at": 1754400000,
                        }
                    ],
                    "total": 1,
                },
            )
        if request.url.path == "/api/sessions/20260805_real/messages":
            return httpx.Response(
                200,
                json={
                    "messages": [
                        {"id": "m1", "role": "user", "content": "salut"},
                        {
                            "id": "m2",
                            "role": "assistant",
                            "content": [
                                {"type": "text", "text": "bonjour"},
                                {"type": "tool_use", "name": "terminal"},
                            ],
                        },
                    ]
                },
            )
        if request.url.path == "/api/sessions/20260805_real" and request.method == "PATCH":
            return httpx.Response(200, json={"ok": True})
        if request.url.path == "/api/model/options":
            return httpx.Response(
                200,
                json={
                    "providers": [
                        {
                            "slug": "deepseek",
                            "name": "DeepSeek",
                            "is_current": True,
                            "models": ["deepseek/deepseek-v4-flash"],
                        },
                        {
                            "slug": "nous",
                            "name": "Nous Portal",
                            "is_current": False,
                            "models": ["anthropic/claude-sonnet-5"],
                        },
                    ]
                },
            )
        if request.url.path == "/api/model/set":
            return httpx.Response(200, json={"ok": True})
        if request.url.path == "/api/files":
            return httpx.Response(
                200,
                json={
                    "entries": [
                        {
                            "name": "notes.md",
                            "path": "/Users/x/notes.md",
                            "is_directory": False,
                            "size": 12,
                            "mime_type": "text/plain",
                        }
                    ]
                },
            )
        if request.url.path == "/api/files/read":
            return httpx.Response(
                200,
                json={"name": "notes.md", "path": "/x/notes.md", "data_url": "data:text/plain;base64,Y29udGVudQ=="},
            )
        return httpx.Response(404, json={"detail": "not mocked"})

    transport = httpx.MockTransport(fake_handler)
    bridge_main._dashboard = DashboardClient(base_url="http://dashboard.test", token="t")  # type: ignore[assignment]
    bridge_main._dashboard._client = httpx.AsyncClient(transport=transport, timeout=5)

    from fastapi.testclient import TestClient

    with TestClient(bridge_main.create_app()) as test_client:
        yield test_client

    bridge_main._reset_runtime_for_tests()


def test_health(client):
    resp = client.get("/api/mobile/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True


def test_sessions_list(client):
    resp = client.get("/api/mobile/sessions")
    assert resp.status_code == 200
    sessions = resp.json()["sessions"]
    assert len(sessions) == 1
    row = sessions[0]
    assert row["id"] == "20260805_real"
    assert row["title"] == "Session réelle"
    assert "telegram" in row["subtitle"]
    assert row["pinned"] is False
    assert row["status"] == "running"


def test_session_messages_filtered(client):
    resp = client.get("/api/mobile/sessions/20260805_real/messages")
    assert resp.status_code == 200
    messages = resp.json()["messages"]
    assert len(messages) == 2
    assert messages[0]["role"] == "user"
    assert messages[0]["text"] == "salut"
    assert isinstance(messages[0]["id"], str)
    assert "createdAt" in messages[0]
    assert messages[1]["role"] == "assistant"
    assert messages[1]["text"] == "bonjour"


def test_new_chat_and_stop(client):
    created = client.post("/api/mobile/new-chat", json={})
    assert created.status_code == 200
    sid = created.json()["sessionID"]
    assert sid

    stopped = client.post("/api/mobile/stop", json={"sessionID": sid})
    assert stopped.status_code == 200
    assert stopped.json()["detail"] == "Stop requested"
    assert bridge_main._engine.cancelled == [sid]  # type: ignore[union-attr]


def test_approval_reply_validation(client):
    # invalid verdict
    bad = client.post("/api/mobile/approvals/abc/reply", json={"verdict": "maybe"})
    assert bad.status_code == 400
    # unknown id
    unknown = client.post("/api/mobile/approvals/nope/reply", json={"verdict": "once"})
    assert unknown.status_code == 404


def test_models_and_files(client):
    models = client.get("/api/mobile/models").json()
    assert len(models["models"]) == 2
    assert "deepseek" in models["providers"]
    assert models["models"][0]["displayName"] == "deepseek-v4-flash"

    set_resp = client.post("/api/mobile/model", json={"model": "deepseek:deepseek-v4-flash"})
    assert set_resp.status_code == 200

    files = client.get("/api/mobile/files").json()
    assert files["files"][0]["label"] == "notes.md"
    assert files["files"][0]["kind"] == "text"

    content = client.get("/api/mobile/files/read", params={"path": "notes.md"}).json()
    assert content["content"] == "contenu"


def test_rename_pin_archive(client):
    renamed = client.post("/api/mobile/sessions/20260805_real/rename", json={"title": "Nouveau"})
    assert renamed.status_code == 200
    assert renamed.json()["title"] == "Nouveau"

    pinned = client.post("/api/mobile/sessions/20260805_real/pin", json={"pinned": True})
    assert pinned.status_code == 200
    assert pinned.json()["pinned"] is True

    archived = client.post("/api/mobile/sessions/20260805_real/archive", json={"archived": True})
    assert archived.status_code == 200
    assert archived.json()["archived"] is True


# ---------------------------------------------------------------------------
# Remote tunnel routes (cloudflared / ngrok — no VPN, no Tailscale)
# ---------------------------------------------------------------------------


class _FakeTunnelProc:
    """Minimal stand-in for asyncio.subprocess.Process (terminate/wait/kill)."""

    def __init__(self) -> None:
        self.returncode = None

    def terminate(self) -> None:
        self.returncode = -15

    def kill(self) -> None:
        self.returncode = -9

    async def wait(self) -> int:
        return self.returncode or 0


async def _fake_spawn(bin_path: str, local_url: str):
    return ("cloudflared", _FakeTunnelProc(), "https://abc123.trycloudflare.com")


def test_bridge_tunnel_status_idle(client):
    client.post("/api/mobile/tunnel/stop")  # clean state
    resp = client.get("/api/mobile/tunnel/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["active"] is False
    assert data["publicUrl"] == ""
    assert data["localUrl"] == "http://127.0.0.1:8766"


def test_bridge_tunnel_start_missing_binary(client, monkeypatch):
    client.post("/api/mobile/tunnel/stop")
    monkeypatch.setattr(bridge_main, "_find_tunnel_bin", lambda: None)
    resp = client.post("/api/mobile/tunnel/start")
    assert resp.status_code == 400
    assert "cloudflared" in resp.json()["detail"]


def test_bridge_tunnel_start_stop_flow(client, monkeypatch):
    client.post("/api/mobile/tunnel/stop")
    monkeypatch.setattr(bridge_main, "_find_tunnel_bin", lambda: "/usr/local/bin/cloudflared")
    monkeypatch.setattr(bridge_main, "_spawn_tunnel", _fake_spawn)

    resp = client.post("/api/mobile/tunnel/start")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["active"] is True
    assert data["provider"] == "cloudflared"
    assert data["publicUrl"] == "https://abc123.trycloudflare.com"

    # A bridge-owned reverse proxy is listening on an ephemeral loopback port.
    proxy = bridge_main._tunnel_proxy
    assert proxy is not None
    assert proxy.port > 0

    status = client.get("/api/mobile/tunnel/status").json()
    assert status["active"] is True

    stop = client.post("/api/mobile/tunnel/stop").json()
    assert stop["stopped"] is True
    assert bridge_main._tunnel_proxy is None
    assert client.get("/api/mobile/tunnel/status").json()["active"] is False

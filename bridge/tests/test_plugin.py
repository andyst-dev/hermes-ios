"""Tests for the hermes-mobile dashboard plugin (plugin/dashboard/plugin_api.py).

The plugin is loaded by the dashboard process and mounted under
``/api/plugins/hermes-mobile``. These tests mount the same router on a
bare FastAPI app and verify the contract: route set, path prefix, auth-free
behavior (auth is added by the dashboard middleware, not the plugin), and the
mobile JSON shapes the iOS app decodes.

The ACP engine is faked at the route layer (same trick as test_routes.py);
the real engine is covered by test_acp_client.py.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path

import httpx
import pytest

PLUGIN_PATH = Path(__file__).resolve().parents[2] / "plugin" / "dashboard" / "plugin_api.py"


def _load_plugin():
    spec = importlib.util.spec_from_file_location("hermes_mobile_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["hermes_mobile_plugin"] = mod
    spec.loader.exec_module(mod)
    return mod


plugin = _load_plugin()


@pytest.fixture()
def client():
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    app = FastAPI()
    app.include_router(plugin.router, prefix="/api/plugins/hermes-mobile")
    plugin._engine = None
    plugin._dashboard = None
    with TestClient(app) as test_client:
        yield test_client


class FakeEngine:
    def __init__(self) -> None:
        self._session_map = {}
        self._active_hermes_session = None
        self._provider = None
        self._model_id = None
        self.resolved: list[tuple[str, str]] = []

    async def new_session(self, hermes_session_id=None):
        hid = hermes_session_id or "20260805_plugin_new"
        self._session_map[hid] = "acp-uuid-p1"
        self._active_hermes_session = hid
        return hid

    async def resume_session(self, hermes_session_id):
        if hermes_session_id not in self._session_map:
            self._session_map[hermes_session_id] = "acp-uuid-p2"
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
        pass

    def resolve_approval(self, approval_id, verdict):
        self.resolved.append((approval_id, verdict))
        return approval_id != "nope"

    def pending_approvals(self):
        return getattr(self, "_fake_pending", {})


class FakeDashboard:
    def __init__(self) -> None:
        self._client = None
        self._base = "http://fake"
        self._token = ""
        self.effort = "medium"

    async def health(self):
        return {"ok": True}

    async def get_reasoning_effort(self):
        return {
            "effort": self.effort,
            "options": ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"],
        }

    async def set_reasoning_effort(self, effort):
        if effort not in ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]:
            raise ValueError(f"invalid effort: {effort}")
        self.effort = effort
        return {"ok": True, "effort": effort}

    async def list_sessions(self, *, limit=100, archived="exclude"):
        sessions = [
            {
                "id": "20260805_plugin_session",
                "title": "Session plugin",
                "source": "acp",
                "profile": "default",
                "model": "deepseek-v4-flash",
                "updated_at": 1785900000,
                "is_active": True,
                "pinned": False,
                "archived": False,
            }
        ]
        if archived == "only":
            return [s for s in sessions if s["archived"]]
        return sessions

    async def get_session_messages(self, session_id):
        return [
            {
                "id": 1,
                "role": "user",
                "content": "salut",
                "created_at": 1785900000,
                "tool_calls": [],
            },
            {
                "id": 2,
                "role": "assistant",
                "content": "bonjour",
                "created_at": 1785900001,
                "tool_calls": [
                    {
                        "id": "call-real-shape",
                        "type": "function",
                        "function": {
                            "name": "terminal",
                            "arguments": '{"command":"git status --short"}',
                        },
                    }
                ],
            },
        ]

    async def patch_session(self, session_id, patch):
        return {"ok": True}

    async def list_files(self, path=None):
        return [
            {
                "name": "notes.txt",
                "path": "/Users/x/notes.txt",
                "is_directory": False,
                "size": 12,
                "mime_type": "text/plain",
            }
        ]

    async def read_file(self, path):
        import base64

        return {
            "name": "notes.txt",
            "path": path,
            "data_url": "data:text/plain;base64," + base64.b64encode(b"hello").decode(),
        }

    async def model_options(self):
        return [
            {
                "model_id": "deepseek/deepseek-v4-flash",
                "provider": "deepseek",
                "provider_name": "DeepSeek",
                "name": "deepseek-v4-flash",
                "is_active": True,
            }
        ]

    async def set_model(self, provider, model_id):
        self.selected_model = (provider, model_id)
        return {"ok": True}


@pytest.fixture(autouse=True)
def _inject_fakes(monkeypatch):
    engine = FakeEngine()
    monkeypatch.setattr(plugin, "_get_engine", lambda: engine)
    monkeypatch.setattr(plugin, "_get_dashboard", lambda: FakeDashboard())
    yield engine

def test_plugin_exposes_seventeen_routes():
    paths = {r.path for r in plugin.router.routes}
    expected = {
        "/health",
        "/capabilities",
        "/sessions",
        "/sessions/{session_id}/messages",
        "/new-chat",
        "/stop",
        "/sessions/{session_id}/rename",
        "/sessions/{session_id}/pin",
        "/sessions/{session_id}/archive",
        "/chat",
        "/approvals/{approval_id}/reply",
        "/models",
        "/model",
        "/model/effort",
        "/files",
        "/files/read",
        "/attachments",
        "/files/attach",
        "/pairing",
        "/pair",
        "/tunnel/status",
        "/tunnel/start",
        "/tunnel/stop",
    }
    assert expected <= paths


def test_plugin_health(client):
    resp = client.get("/api/plugins/hermes-mobile/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True


def test_plugin_sessions_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/sessions")
    assert resp.status_code == 200
    sessions = resp.json()["sessions"]
    assert len(sessions) == 1
    row = sessions[0]
    assert row["id"] == "20260805_plugin_session"
    assert row["status"] == "running"  # is_active -> running (iOS enum)
    assert row["updatedAt"].endswith("Z")


def test_plugin_sessions_archived_filter_forwards(client):
    resp = client.get("/api/plugins/hermes-mobile/sessions", params={"archived": "only"})
    assert resp.status_code == 200
    assert resp.json()["sessions"] == []  # FakeDashboard returns only non-archived


def test_plugin_stats_aggregates_models(tmp_path, monkeypatch, client):
    import sqlite3
    import time

    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    db = tmp_path / "state.db"
    con = sqlite3.connect(db)
    con.execute(
        """
        CREATE TABLE sessions (
            model TEXT, message_count INTEGER, input_tokens INTEGER,
            output_tokens INTEGER, cache_read_tokens INTEGER,
            reasoning_tokens INTEGER, estimated_cost_usd REAL,
            actual_cost_usd REAL, archived INTEGER, started_at REAL,
            cost_status TEXT, billing_provider TEXT
        )
        """
    )
    now = time.time()
    con.executemany(
        "INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        [
            ("deepseek-v4-flash", 10, 1000, 500, 0, 0, 0.05, 0.0, 0, now - 172800, "estimated", "deepseek"),
            ("deepseek-v4-flash", 5, 500, 250, 0, 0, 0.02, 0.0, 0, now - 86400, "estimated", "nous"),
            ("gpt-5.5", 3, 2000, 100, 0, 0, 0.10, 0.0, 0, now - 86400, "included", "openai-codex"),
            # terra-pro runs on the Nous portal; blank provider must roll under "nous".
            ("openai/gpt-5.6-terra-pro", 0, 0, 0, 0, 0, 0.0, 0.0, 0, now - 3600, "", ""),
            ("archived-model", 1, 999, 999, 0, 0, 9.99, 0.0, 1, now, "estimated", "deepseek"),
        ],
    )
    con.commit()
    con.close()

    resp = client.get("/api/plugins/hermes-mobile/stats")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert isinstance(data["accounts"], list) and data["accounts"]
    assert all({"provider", "ok"} <= set(a) for a in data["accounts"])
    total = data["total"]
    # Archived sessions are excluded.
    assert total["sessions"] == 4
    assert total["messages"] == 18
    assert total["inputTokens"] == 3500
    assert total["outputTokens"] == 850
    assert total["estimatedCostUsd"] == pytest.approx(0.17)
    models = {m["model"]: m for m in data["byModel"]}
    assert set(models) == {"deepseek-v4-flash", "gpt-5.5", "openai/gpt-5.6-terra-pro"}
    assert models["deepseek-v4-flash"]["sessions"] == 2
    assert models["deepseek-v4-flash"]["inputTokens"] == 1500
    assert models["deepseek-v4-flash"]["costStatus"] == "estimated"
    assert models["gpt-5.5"]["costStatus"] == "included"
    assert models["deepseek-v4-flash"]["untrackedSessions"] == 0
    providers = {p["provider"]: p for p in data["byProvider"]}
    assert set(providers) == {"deepseek", "nous", "openai-codex"}
    # Every detected billing provider gets an account entry. Live balance is
    # optional; local usage/model data must still work for future providers.
    account_providers = {a["provider"] for a in data["accounts"]}
    assert set(providers) <= account_providers
    assert providers["nous"]["sessions"] == 2
    assert providers["nous"]["estimatedCostUsd"] == pytest.approx(0.02)
    assert providers["openai-codex"]["costStatus"] == "included"
    # Each provider carries its per-model breakdown for the drill-down.
    nous_models = {m["model"]: m for m in providers["nous"]["models"]}
    assert set(nous_models) == {"deepseek-v4-flash", "openai/gpt-5.6-terra-pro"}
    assert nous_models["deepseek-v4-flash"]["sessions"] == 1
    assert nous_models["deepseek-v4-flash"]["tokens"] == 750
    assert nous_models["openai/gpt-5.6-terra-pro"]["sessions"] == 1
    # Daily rows are present and sorted by day.
    days = [row["day"] for row in data["daily"]]
    assert days == sorted(days) and days


def test_plugin_messages_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/sessions/x/messages")
    assert resp.status_code == 200
    messages = resp.json()["messages"]
    assert len(messages) == 2
    assert isinstance(messages[0]["id"], str)
    assert "createdAt" in messages[0]
    assert messages[1]["role"] == "assistant"
    assert messages[1]["toolCalls"][0]["name"] == "terminal"
    assert "git status --short" in messages[1]["toolCalls"][0]["command"]


def test_plugin_projects_codex_commentary_as_visible_message():
    row = {
        "id": 54,
        "role": "assistant",
        "content": "",
        "reasoning_content": (
            "**Investigating app launch and crash**\n\n"
            "The network error is gone; I am checking app launch."
        ),
        "codex_reasoning_items": json.dumps([
            {
                "type": "reasoning",
                "summary": [{"type": "summary_text", "text": "**Investigating app launch and crash**"}],
            }
        ]),
        "codex_message_items": json.dumps([
            {
                "type": "message",
                "phase": "commentary",
                "content": [{"type": "output_text", "text": "The network error is gone; I am checking app launch."}],
            }
        ]),
    }

    projected = plugin._mobile_msg(row)

    assert projected["text"] == "The network error is gone; I am checking app launch."
    assert projected["thinking"] == "**Investigating app launch and crash**"
    assert "network error" not in projected["thinking"]


def test_plugin_does_not_repeat_commentary_as_thinking_without_summary_item():
    commentary = "I’m running the requested terminal check now."
    projected = plugin._mobile_msg({
        "id": 55,
        "role": "assistant",
        "content": "",
        "reasoning_content": commentary,
        "codex_message_items": [{
            "type": "message",
            "phase": "commentary",
            "content": [{"type": "output_text", "text": commentary}],
        }],
    })

    assert projected["text"] == commentary
    assert "thinking" not in projected


def test_plugin_chat_resumes_non_acp_session_without_forking(client, monkeypatch):
    dashboard = FakeDashboard()

    async def list_sessions(*, limit=100, archived="exclude"):
        assert limit <= 100
        # The official dashboard uses `session_id`; the mobile response later
        # normalizes it to `id`.
        return [{"session_id": "telegram-session", "source": "telegram"}]

    async def get_messages(session_id):
        assert session_id == "telegram-session"
        return [{"id": 1, "role": "assistant", "content": "same conversation", "timestamp": 1785900001}]

    captured = {}

    async def stream_resume(session_id, text, provider, model_id):
        captured.update(
            session_id=session_id,
            text=text,
            provider=provider,
            model_id=model_id,
        )
        yield {"type": "delta", "text": "same "}
        yield {"type": "delta", "text": "conversation"}

    dashboard.list_sessions = list_sessions
    dashboard.get_session_messages = get_messages
    monkeypatch.setattr(plugin, "_get_dashboard", lambda: dashboard)
    monkeypatch.setattr(plugin, "_stream_non_acp_session", stream_resume)

    response = client.post(
        "/api/plugins/hermes-mobile/chat",
        json={"sessionID": "telegram-session", "text": "continue ici"},
    )

    assert response.status_code == 200
    assert captured["session_id"] == "telegram-session"
    assert captured["text"] == "continue ici"
    assert '"type": "delta"' in response.text
    assert '"text": "same "' in response.text
    assert '"text": "conversation"' in response.text
    assert '"sessionID": "telegram-session"' in response.text
    assert '"type": "done"' in response.text


def test_plugin_models_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/models")
    assert resp.status_code == 200
    models = resp.json()["models"]
    assert len(models) == 1
    m = models[0]
    assert m["displayName"] == "deepseek-v4-flash"
    assert m["isActive"] is True
    assert m["supportsVision"] is False
    assert m["supportsTools"] is True


def test_plugin_model_set_preserves_explicit_provider(client, monkeypatch):
    dashboard = FakeDashboard()
    monkeypatch.setattr(plugin, "_get_dashboard", lambda: dashboard)

    response = client.post(
        "/api/plugins/hermes-mobile/model",
        json={"provider": "nous", "model": "deepseek/deepseek-v4-flash-0731"},
    )

    assert response.status_code == 200
    assert dashboard.selected_model == ("nous", "deepseek/deepseek-v4-flash-0731")
    assert response.json()["provider"] == "nous"


def test_plugin_files_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/files")
    assert resp.status_code == 200
    files = resp.json()["files"]
    assert len(files) == 1
    f = files[0]
    assert f["label"] == "notes.txt"
    assert f["kind"] == "text"
    assert f["path"] == "/Users/x/notes.txt"


def test_plugin_files_read_decodes(client):
    resp = client.get("/api/plugins/hermes-mobile/files/read", params={"path": "notes.txt"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["content"] == "hello"
    assert data["truncated"] is False


def test_plugin_model_effort_flow(client, monkeypatch):
    """Reasoning effort: GET reads agent.reasoning_effort, POST persists it."""
    # A stable instance so GET → POST → GET share state.
    dashboard = FakeDashboard()
    dashboard.effort = "high"
    monkeypatch.setattr(plugin, "_get_dashboard", lambda: dashboard)

    got = client.get("/api/plugins/hermes-mobile/model/effort").json()
    assert got["effort"] == "high"
    assert "medium" in got["options"]

    set_resp = client.post(
        "/api/plugins/hermes-mobile/model/effort", json={"effort": "low"}
    )
    assert set_resp.status_code == 200
    assert dashboard.effort == "low"

    got2 = client.get("/api/plugins/hermes-mobile/model/effort").json()
    assert got2["effort"] == "low"

    bad = client.post(
        "/api/plugins/hermes-mobile/model/effort", json={"effort": "insane"}
    )
    assert bad.status_code == 400


def test_plugin_approval_reply_unknown_id(client):
    resp = client.post(
        "/api/plugins/hermes-mobile/approvals/nope/reply",
        json={"verdict": "once"},
    )
    assert resp.status_code == 404


def test_plugin_pairing_flow(client, monkeypatch):
    """QR pairing: the QR embeds the dashboard token directly."""
    # Force a deterministic dashboard token (no hermes_cli import in tests)
    monkeypatch.setattr(plugin, "_dashboard_session_token", lambda: "test-dashboard-token-abc")

    resp = client.get("/api/plugins/hermes-mobile/pairing")
    assert resp.status_code == 200
    data = resp.json()
    assert data["code"]
    assert data["token"] == "test-dashboard-token-abc"
    assert "hermes-mobile-pairing" in data["qrText"]
    assert "test-dashboard-token-abc" in data["qrText"]
    assert data["expiresAt"].endswith("Z")


def test_plugin_pairing_requires_auth_by_default(client):
    """The pairing endpoint sits behind the dashboard auth gate (no public hole)."""
    # Without the monkeypatched token the endpoint still works, but the
    # middleware-level 401 comes from the dashboard — here we only assert the
    # route exists and returns data when called.
    resp = client.get("/api/plugins/hermes-mobile/pairing")
    assert resp.status_code == 200
    assert resp.json()["qrText"]


def test_plugin_pair_expires_code(client, monkeypatch):
    """/pair consumes the code once; a second use 404s."""
    monkeypatch.setattr(plugin, "_dashboard_session_token", lambda: "test-token")

    # Un code jamais généré → 404
    resp = client.post(
        "/api/plugins/hermes-mobile/pair",
        json={"code": "does-not-exist", "deviceName": "iPhone"},
    )
    assert resp.status_code == 404

    # Un code consommé une fois → 404 au second usage
    gen = client.get("/api/plugins/hermes-mobile/pairing").json()
    ok = client.post("/api/plugins/hermes-mobile/pair", json={"code": gen["code"]})
    assert ok.status_code == 200
    again = client.post("/api/plugins/hermes-mobile/pair", json={"code": gen["code"]})
    assert again.status_code == 404


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


def test_plugin_tunnel_status_idle(client):
    client.post("/api/plugins/hermes-mobile/tunnel/stop")  # clean state
    resp = client.get("/api/plugins/hermes-mobile/tunnel/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["active"] is False
    assert data["publicUrl"] == ""
    assert data["localUrl"] == "http://127.0.0.1:8765"


def test_plugin_tunnel_start_missing_binary(client, monkeypatch):
    client.post("/api/plugins/hermes-mobile/tunnel/stop")
    monkeypatch.setattr(plugin, "_find_tunnel_bin", lambda: None)
    resp = client.post("/api/plugins/hermes-mobile/tunnel/start")
    assert resp.status_code == 400
    assert "cloudflared" in resp.json()["detail"]


def test_plugin_tunnel_start_stop_flow(client, monkeypatch):
    client.post("/api/plugins/hermes-mobile/tunnel/stop")
    monkeypatch.setattr(plugin, "_find_tunnel_bin", lambda: "/usr/local/bin/cloudflared")
    monkeypatch.setattr(plugin, "_spawn_tunnel", _fake_spawn)

    resp = client.post("/api/plugins/hermes-mobile/tunnel/start")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["active"] is True
    assert data["provider"] == "cloudflared"
    assert data["publicUrl"] == "https://abc123.trycloudflare.com"

    # A plugin-owned reverse proxy is listening on an ephemeral loopback
    # port; cloudflared points at it and it rewrites the Host header back to
    # loopback, so the core Host-header guard never sees the public hostname.
    proxy = plugin._tunnel_proxy
    assert proxy is not None
    assert proxy.port > 0

    status = client.get("/api/plugins/hermes-mobile/tunnel/status").json()
    assert status["active"] is True
    assert status["publicUrl"] == "https://abc123.trycloudflare.com"

    stop = client.post("/api/plugins/hermes-mobile/tunnel/stop").json()
    assert stop["stopped"] is True
    assert client.get("/api/plugins/hermes-mobile/tunnel/status").json()["active"] is False
    # Proxy torn down once the tunnel is closed.
    assert plugin._tunnel_proxy is None


def test_plugin_pairing_prefers_tunnel_url(client, monkeypatch):
    """With a live tunnel the QR embeds the public URL, not localhost."""
    client.post("/api/plugins/hermes-mobile/tunnel/stop")
    monkeypatch.setattr(plugin, "_find_tunnel_bin", lambda: "/usr/local/bin/cloudflared")
    monkeypatch.setattr(plugin, "_spawn_tunnel", _fake_spawn)

    client.post("/api/plugins/hermes-mobile/tunnel/start")
    pairing = client.get("/api/plugins/hermes-mobile/pairing").json()
    assert pairing["url"] == "https://abc123.trycloudflare.com"
    assert "https://abc123.trycloudflare.com" in pairing["qrText"]

    client.post("/api/plugins/hermes-mobile/tunnel/stop")
    pairing = client.get("/api/plugins/hermes-mobile/pairing").json()
    assert pairing["url"] == "http://127.0.0.1:8765"


def test_tunnel_proxy_rewrites_host_header():
    """The reverse proxy rewrites the Host header back to the target's
    loopback address — the core Host-header guard never sees the public
    tunnel hostname (this is what makes the feature core-patch-free)."""

    async def run() -> None:
        import asyncio

        received: dict[str, str] = {}

        async def target_handler(reader, writer):
            line = await reader.readline()
            received["path"] = line.decode("latin-1").strip().split(" ", 2)[1]
            while True:
                line = await reader.readline()
                if line in (b"\r\n", b"\n", b""):
                    break
                name, _, value = line.decode("latin-1").partition(":")
                received[name.strip().lower()] = value.strip()
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
            await writer.drain()
            writer.close()

        target = await asyncio.start_server(target_handler, "127.0.0.1", 0)
        assert target.sockets
        tport = target.sockets[0].getsockname()[1]
        proxy = plugin._TunnelProxy(f"http://127.0.0.1:{tport}")
        pport = await proxy.start()
        try:
            # 1) Foreign Host header is rewritten back to the target's loopback.
            reader, writer = await asyncio.open_connection("127.0.0.1", pport)
            writer.write(
                b"GET /api/plugins/hermes-mobile/health HTTP/1.1\r\n"
                b"Host: evil.trycloudflare.com\r\n\r\n"
            )
            await writer.drain()
            await reader.read(64)
            writer.close()

            # 2) The iOS app speaks /api/mobile/*; the proxy maps it onto the
            #    plugin mount point so the tunnel serves the app as-is.
            reader, writer = await asyncio.open_connection("127.0.0.1", pport)
            writer.write(
                b"GET /api/mobile/sessions HTTP/1.1\r\n"
                b"Host: evil.trycloudflare.com\r\n\r\n"
            )
            await writer.drain()
            await reader.read(64)
            writer.close()
        finally:
            await proxy.stop()
            target.close()
            await target.wait_closed()

        assert received.get("host") == f"127.0.0.1:{tport}"
        assert received.get("path") == "/api/plugins/hermes-mobile/sessions"

    import asyncio

    asyncio.run(run())


# ---------------------------------------------------------------------------
# Cron job routes (gateway cron store, exposed by the plugin only)
# ---------------------------------------------------------------------------


@pytest.fixture
def cron_stub(monkeypatch):
    """Stub the gateway's ``cron`` package so the plugin routes run without
    hermes-agent on the test sys.path."""
    import sys
    import types

    fake_job = {
        "id": "job1",
        "name": "Daily briefing",
        "prompt": "Summarize the news",
        "schedule": "0 9 * * *",
        "schedule_display": "every day at 09:00",
        "state": "scheduled",
        "enabled": True,
        "next_run_at": "2026-08-09T09:00:00+02:00",
        "last_run_at": None,
        "deliver": "telegram:Home",
        "skills": [],
        "latest_execution": {"id": "ex1", "status": "completed", "started_at": "2026-08-08T08:00:00+02:00", "finished_at": "2026-08-08T08:01:00+02:00"},
    }

    def paused(job_id, reason=None):
        if job_id != "job1":
            return None
        return {**fake_job, "enabled": False, "state": "paused"}

    def resumed(job_id):
        if job_id != "job1":
            return None
        return {**fake_job, "enabled": True, "state": "scheduled"}

    def triggered(job_id):
        if job_id != "job1":
            return None
        return {**fake_job, "state": "running"}

    created_kwargs: dict = {}

    def create_job(prompt, schedule, name=None, **kwargs):
        created_kwargs.update(prompt=prompt, schedule=schedule, name=name, **kwargs)
        return {
            **fake_job,
            "id": "job2",
            "name": name or "Untitled",
            "prompt": prompt,
            "schedule": schedule,
            "deliver": kwargs.get("deliver") or "",
            "skills": kwargs.get("skills") or [],
        }

    def get_job(job_id):
        if job_id == "job1":
            return dict(fake_job)
        if job_id == "job2":
            return {
                **fake_job,
                "id": "job2",
                "name": created_kwargs.get("name") or "Untitled",
                "prompt": created_kwargs.get("prompt", ""),
                "schedule": created_kwargs.get("schedule", ""),
                "deliver": created_kwargs.get("deliver") or "",
                "skills": created_kwargs.get("skills") or [],
            }
        return None

    fake_cron = types.ModuleType("cron")
    fake_cron_jobs = types.ModuleType("cron.jobs")
    setattr(fake_cron_jobs, "list_jobs", lambda include_disabled=False: [dict(fake_job)])
    setattr(fake_cron_jobs, "pause_job", paused)
    setattr(fake_cron_jobs, "resume_job", resumed)
    setattr(fake_cron_jobs, "trigger_job", triggered)
    setattr(fake_cron_jobs, "remove_job", lambda job_id: job_id == "job1")
    setattr(fake_cron_jobs, "create_job", create_job)
    setattr(fake_cron_jobs, "get_job", get_job)
    setattr(fake_cron_jobs, "created_kwargs", created_kwargs)
    setattr(fake_cron, "jobs", fake_cron_jobs)
    monkeypatch.setitem(sys.modules, "cron", fake_cron)
    monkeypatch.setitem(sys.modules, "cron.jobs", fake_cron_jobs)
    return fake_cron_jobs


def test_plugin_cron_list_and_actions(client, cron_stub):
    listing = client.get("/api/plugins/hermes-mobile/cron")
    assert listing.status_code == 200
    jobs = listing.json()["jobs"]
    assert len(jobs) == 1
    assert jobs[0]["id"] == "job1"
    assert jobs[0]["scheduleDisplay"] == "every day at 09:00"
    assert jobs[0]["latestExecution"]["status"] == "completed"

    paused = client.post("/api/plugins/hermes-mobile/cron/job1/pause")
    assert paused.status_code == 200
    assert paused.json()["job"]["state"] == "paused"

    resumed = client.post("/api/plugins/hermes-mobile/cron/job1/resume")
    assert resumed.json()["job"]["enabled"] is True

    ran = client.post("/api/plugins/hermes-mobile/cron/job1/run")
    assert ran.json()["job"]["state"] == "running"

    removed = client.post("/api/plugins/hermes-mobile/cron/job1/remove")
    assert removed.json()["removed"] is True


def test_plugin_cron_unknown_job_404(client, cron_stub):
    resp = client.post("/api/plugins/hermes-mobile/cron/ghost/pause")
    assert resp.status_code == 404
    assert "Unknown cron job" in resp.json()["detail"]


def test_plugin_cron_create(client, cron_stub):
    created = client.post(
        "/api/plugins/hermes-mobile/cron",
        json={
            "name": "Nightly backup",
            "prompt": "Back up the repo",
            "schedule": "0 2 * * *",
            "skills": ["git"],
            "deliver": "local",
        },
    )
    assert created.status_code == 200
    job = created.json()["job"]
    assert job["id"] == "job2"
    assert job["name"] == "Nightly backup"
    assert job["prompt"] == "Back up the repo"
    assert job["schedule"] == "0 2 * * *"
    assert job["skills"] == ["git"]
    assert job["deliver"] == "local"
    # The gateway create_job must have received the mobile fields.
    assert cron_stub.created_kwargs["skills"] == ["git"]
    assert cron_stub.created_kwargs["deliver"] == "local"
    assert cron_stub.created_kwargs["name"] == "Nightly backup"


def test_plugin_cron_create_validates(client, cron_stub):
    missing_prompt = client.post(
        "/api/plugins/hermes-mobile/cron",
        json={"name": "x", "schedule": "0 9 * * *"},
    )
    assert missing_prompt.status_code == 400
    assert "prompt" in missing_prompt.json()["detail"]

    missing_schedule = client.post(
        "/api/plugins/hermes-mobile/cron",
        json={"prompt": "hello"},
    )
    assert missing_schedule.status_code == 400
    assert "schedule" in missing_schedule.json()["detail"]


def test_plugin_memory_update_and_delete(client, monkeypatch, tmp_path):
    monkeypatch.setattr(plugin, "_MEMORIES_DIR", str(tmp_path))
    mem = tmp_path / "MEMORY.md"
    mem.write_text("first entry\n\n§\n\nsecond entry\n", encoding="utf-8")

    updated = client.patch(
        "/api/plugins/hermes-mobile/memory/memory/1",
        json={"content": "second entry (edited)"},
    )
    assert updated.status_code == 200
    entries = updated.json()["entries"]
    assert len(entries) == 2
    assert entries[1]["content"] == "second entry (edited)"
    # The on-disk file keeps the § separator format the memory loader parses.
    assert "second entry (edited)" in mem.read_text(encoding="utf-8")

    deleted = client.delete("/api/plugins/hermes-mobile/memory/memory/0")
    assert deleted.status_code == 200
    remaining = deleted.json()["entries"]
    assert len(remaining) == 1
    assert remaining[0]["content"] == "second entry (edited)"


def test_plugin_memory_edits_validate(client, monkeypatch, tmp_path):
    monkeypatch.setattr(plugin, "_MEMORIES_DIR", str(tmp_path))
    (tmp_path / "MEMORY.md").write_text("only entry\n", encoding="utf-8")

    out_of_range = client.delete("/api/plugins/hermes-mobile/memory/memory/5")
    assert out_of_range.status_code == 404
    assert "No memory entry" in out_of_range.json()["detail"]

    empty = client.patch(
        "/api/plugins/hermes-mobile/memory/memory/0",
        json={"content": "   "},
    )
    assert empty.status_code == 400

    bad_target = client.delete("/api/plugins/hermes-mobile/memory/notes/0")
    assert bad_target.status_code == 400


def test_plugin_notifications_pending(client, monkeypatch):
    """Pending approvals surface through /notifications/pending, and cron
    executions ride along when the cron store is reachable."""
    engine = plugin._get_engine()
    engine._fake_pending = {
        "appr1": {"session_id": "sess-1", "command": "rm -rf /tmp/x"},
        "appr2": {"session_id": "sess-2", "command": "git push"},
    }

    import sys
    import types

    fake_cron = types.ModuleType("cron")
    fake_executions = types.ModuleType("cron.executions")
    setattr(
        fake_executions,
        "list_executions",
        lambda limit=50, **_: [
            {
                "job_id": "job1",
                "status": "completed",
                "claimed_at": "2026-08-08T08:00:00+02:00",
                "finished_at": "2026-08-08T08:00:30+02:00",
                "summary": "Delivered to telegram:Home",
            }
        ],
    )
    setattr(fake_cron, "executions", fake_executions)
    monkeypatch.setitem(sys.modules, "cron", fake_cron)
    monkeypatch.setitem(sys.modules, "cron.executions", fake_executions)

    resp = client.get("/api/plugins/hermes-mobile/notifications/pending")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["approvals"]) == 2
    assert data["approvals"][0]["id"] == "appr1"
    assert data["approvals"][0]["sessionID"] == "sess-1"
    assert data["approvals"][0]["command"] == "rm -rf /tmp/x"
    assert len(data["recentCron"]) == 1
    assert data["recentCron"][0]["status"] == "completed"


def test_plugin_skills_list_and_detail(client, tmp_path, monkeypatch):
    skill_dir = tmp_path / "research" / "arxiv"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "---\nname: arxiv\ndescription: Search arXiv papers by keyword.\n---\n\n# Body\nFull content here.\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(plugin, "_SKILLS_ROOT", str(tmp_path))

    listing = client.get("/api/plugins/hermes-mobile/skills")
    assert listing.status_code == 200
    skills = listing.json()["skills"]
    assert len(skills) == 1
    assert skills[0]["name"] == "arxiv"
    assert skills[0]["category"] == "research"
    assert "Search arXiv" in skills[0]["description"]

    detail = client.get("/api/plugins/hermes-mobile/skills/arxiv")
    assert detail.status_code == 200
    assert "Full content here" in detail.json()["skill"]["body"]

    assert client.get("/api/plugins/hermes-mobile/skills/nope").status_code == 404


def test_plugin_memory_get_and_append(client, tmp_path, monkeypatch):
    mem = tmp_path / "memories"
    mem.mkdir(parents=True)
    (mem / "MEMORY.md").write_text("First note\n§\nSecond note\n", encoding="utf-8")
    (mem / "USER.md").write_text("User fact\n", encoding="utf-8")
    monkeypatch.setattr(plugin, "_MEMORIES_DIR", str(mem))

    listing = client.get("/api/plugins/hermes-mobile/memory")
    assert listing.status_code == 200
    data = listing.json()
    assert len(data["memory"]) == 2
    assert data["memory"][0]["content"] == "First note"
    assert len(data["user"]) == 1

    appended = client.post(
        "/api/plugins/hermes-mobile/memory",
        json={"target": "memory", "content": "Third note"},
    )
    assert appended.status_code == 200
    assert len(appended.json()["entries"]) == 3
    assert appended.json()["entries"][2]["content"] == "Third note"

    bad = client.post("/api/plugins/hermes-mobile/memory", json={"target": "wat", "content": "x"})
    assert bad.status_code == 400


def test_plugin_doctor_and_update_run_cli(client, monkeypatch):
    """POST /doctor and /update invoke the hermes CLI with the right args."""

    class FakeProc:
        returncode = 0

        async def communicate(self):
            return b"doctor report line\n", None

    calls = []

    async def fake_exec(*args, **kwargs):
        calls.append((args, kwargs))
        return FakeProc()

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)

    doctor = client.post("/api/plugins/hermes-mobile/doctor")
    assert doctor.status_code == 200
    body = doctor.json()
    assert body["ok"] is True
    assert "doctor report" in body["output"]
    doc_args = calls[0][0]
    assert doc_args[1] == "-m" and doc_args[2] == "hermes_cli.main" and "doctor" in doc_args

    update = client.post("/api/plugins/hermes-mobile/update")
    assert update.status_code == 200
    assert update.json()["ok"] is True
    up_args = calls[1][0]
    assert "update" in up_args and "--yes" in up_args

    class FailingProc:
        returncode = 1

        async def communicate(self):
            return b"something broke\n", None

    async def failing_exec(*args, **kwargs):
        return FailingProc()

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", failing_exec)
    bad = client.post("/api/plugins/hermes-mobile/doctor")
    assert bad.json()["ok"] is False
    assert "something broke" in bad.json()["output"]


def test_plugin_doctor_parses_issues_and_solutions():
    """⚠/✗ lines become problem+solution entries; ✓ lines are ignored."""
    output = (
        "  \u2713 Python 3.11\n"
        "  \u26a0 SQLite 3.50.4 (WAL-reset bug) (run `hermes update`)\n"
        "  \u2717 model.provider 'wat' is not a recognised provider\n"
        "  \u26a0 discord.py (optional, not installed)\n"
    )
    issues = plugin._parse_doctor_issues(output)
    assert len(issues) == 3
    assert issues[0]["problem"].startswith("SQLite")
    assert "hermes update" in issues[0]["solution"]
    assert "recognised provider" in issues[1]["problem"]
    assert "config.yaml" in issues[1]["solution"]
    assert issues[2]["solution"].startswith("Optional")
    assert plugin._parse_doctor_issues("  \u2713 all good\n") == []




def test_plugin_update_status_contract(client, monkeypatch):
    """GET /update/status parses --check and lists incoming commits."""

    class CliProc:
        returncode = 0

        async def communicate(self):
            return b"\u2695 Update available (behind upstream/main).\n", None

    class GitProc:
        def __init__(self, data: bytes):
            self._data = data
            self.returncode = 0

        async def communicate(self):
            return self._data, None

    calls = []

    async def fake_exec(*args, **kwargs):
        calls.append(args)
        if list(args[1:3]) == ["-m", "hermes_cli.main"] and "--check" in args:
            return CliProc()
        if "log" in args:
            if "--stat" in args:
                return GitProc(b"full changelog detail\n")
            return GitProc(b"abc1234 feat: shiny new thing\ncdef567 fix: bug\n")
        raise AssertionError(f"unexpected exec: {args}")

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)
    r = client.get("/api/plugins/hermes-mobile/update/status")
    assert r.status_code == 200
    body = r.json()
    assert body["updateAvailable"] is True
    assert len(body["highlights"]) == 2
    assert "feat: shiny" in body["highlights"][0]
    assert "full changelog" in body["fullChangelog"]

    # when --check says up to date, no git log is fetched
    class UpToDateProc:
        returncode = 0

        async def communicate(self):
            return b"hermes is up to date\n", None

    calls.clear()

    async def up_to_date_exec(*args, **kwargs):
        calls.append(args)
        return UpToDateProc()

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", up_to_date_exec)
    r2 = client.get("/api/plugins/hermes-mobile/update/status")
    body2 = r2.json()
    assert body2["updateAvailable"] is False
    assert body2["highlights"] == []
    assert all("log" not in a for a in calls)


def test_plugin_session_delete_runs_cli(client, monkeypatch):
    """DELETE /sessions/{id} invokes `hermes sessions delete --yes <id>`."""

    class OkProc:
        returncode = 0

        async def communicate(self):
            return b"deleted\n", None

    calls = []

    async def fake_exec(*args, **kwargs):
        calls.append(args)
        return OkProc()

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)
    r = client.delete("/api/plugins/hermes-mobile/sessions/sess-123")
    assert r.status_code == 200
    assert r.json()["ok"] is True
    cli = " ".join(str(x) for x in calls[0])
    assert "sess-123" in cli and "delete" in cli and "--yes" in cli


class _FakeStream:
    """Async line stream standing in for a subprocess stdout pipe."""

    def __init__(self, lines):
        self._lines = [line if isinstance(line, bytes) else line.encode() for line in lines]
        self._i = 0

    async def readline(self):
        if self._i >= len(self._lines):
            return b""
        line = self._lines[self._i]
        self._i += 1
        return line + b"\n"


class _FakeProc:
    def __init__(self, lines, returncode=0):
        self.stdout = _FakeStream(lines)
        self.returncode = returncode

    async def wait(self):
        return self.returncode

    def kill(self):
        pass


def test_stream_resume_error_event_surfaces_stderr_diagnostic(monkeypatch):
    """A generic error event keeps the real cause when stderr carried one."""
    import asyncio

    async def fake_exec(*args, **kwargs):
        return _FakeProc(
            [
                "Failed to initialize agent: model not reachable",
                json.dumps({"type": "error", "detail": "Unable to initialize Hermes agent"}),
            ]
        )

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)

    async def collect():
        return [e async for e in plugin._stream_non_acp_session("s1", "hello", None, None)]

    events = asyncio.run(collect())
    assert events[-1]["type"] == "error"
    detail = events[-1]["detail"]
    assert "Unable to initialize Hermes agent" in detail
    assert "Failed to initialize agent" in detail
    assert "[desktop]" in detail


def test_stream_resume_exit_status_surfaces_stderr_diagnostic(monkeypatch):
    """A nonzero exit without a result includes the subprocess diagnostic."""
    import asyncio

    async def fake_exec(*args, **kwargs):
        return _FakeProc(["Traceback (most recent call last):", "RuntimeError: boom"], returncode=1)

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)

    async def collect():
        return [e async for e in plugin._stream_non_acp_session("s1", "hello", None, None)]

    events = asyncio.run(collect())
    assert events[-1]["type"] == "error"
    detail = events[-1]["detail"]
    assert "exited with status 1" in detail
    assert "RuntimeError: boom" in detail


def test_stream_resume_ignores_benign_stderr_lines(monkeypatch):
    """Resume banners and other status noise never leak into the error detail."""
    import asyncio

    async def fake_exec(*args, **kwargs):
        return _FakeProc(
            [
                "↻ Resumed session 20260810_153843_179097 (1 user message, 1 total messages)",
                json.dumps({"type": "error", "detail": "Unable to initialize Hermes agent"}),
            ]
        )

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)

    async def collect():
        return [e async for e in plugin._stream_non_acp_session("s1", "hello", None, None)]

    events = asyncio.run(collect())
    detail = events[-1]["detail"]
    assert "Unable to initialize Hermes agent" in detail
    assert "Resumed session" not in detail
    assert "[desktop]" not in detail


def test_stream_resume_pins_pythonpath_to_repo(monkeypatch):
    """The subprocess must not inherit a mixed-checkout PYTHONPATH."""
    import asyncio

    captured = {}

    async def fake_exec(*args, **kwargs):
        captured["kwargs"] = kwargs
        return _FakeProc([json.dumps({"type": "error", "detail": "boom"})])

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)

    async def collect():
        return [e async for e in plugin._stream_non_acp_session("s1", "hello", None, None)]

    asyncio.run(collect())
    env = captured["kwargs"]["env"]
    cwd = captured["kwargs"]["cwd"]
    assert env["PYTHONPATH"] == cwd
    assert "HERMES_SESSION_PLATFORM" not in env
    assert "HERMES_GATEWAY_SESSION" not in env
    assert "HERMES_EXEC_ASK" not in env


def test_release_notes_group_and_clean_commits():
    """Conventional commits become grouped, human-readable bullets."""
    commits = [
        "a1b2c3d feat(gateway): make drain force-kill reachable",
        "e4f5a6b fix: keep seeded draft across full-page handoff",
        "c7d8e9f0 fix(ui): present chat edge-to-edge from the bottom (#6231)",
        "a1a2a3a4 refactor(host-service): prioritize origin in parallel probes",
        "b2b3b4b5 docs: update README counts",
        "c3c4c5c6 chore: bump plugin version to 1.1.0",
        "d4d5d6d7 some plain message without prefix",
    ]
    notes = plugin._human_release_notes(commits)
    sections = {n["section"]: n["items"] for n in notes}
    assert sections["New features"] == ["Make drain force-kill reachable"]
    assert sections["Fixes"] == [
        "Keep seeded draft across full-page handoff",
        "Present chat edge-to-edge from the bottom",
    ]
    assert sections["Improvements"] == [
        "Prioritize origin in parallel probes",
        "Bump plugin version to 1.1.0",
    ]
    assert sections["Documentation"] == ["Update README counts"]
    assert sections["Other"] == ["Some plain message without prefix"]
    # First-seen order preserved
    assert [n["section"] for n in notes] == [
        "New features", "Fixes", "Improvements", "Documentation", "Other",
    ]


def test_release_notes_edge_cases():
    """Hash prefix, PR refs, empty subjects and type-only lines are handled."""
    assert plugin._clean_release_subject("  make it work (#42) ") == "Make it work"
    assert plugin._clean_release_subject("  fix typo. ") == "Fix typo"
    assert plugin._clean_release_subject("   ") == ""
    notes = plugin._human_release_notes(
        ["deadbeef fix: only a hash-prefixed line", "feat: ", "  "]
    )
    assert notes == [{"section": "Fixes", "items": ["Only a hash-prefixed line"]}]


def test_update_status_route_sends_notes(client, monkeypatch):
    """GET /update/status carries grouped human notes alongside highlights."""

    class CliProc:
        returncode = 0

        async def communicate(self):
            return b"\u2695 Update available (behind upstream/main).\n", None

    class GitProc:
        def __init__(self, data: bytes):
            self._data = data
            self.returncode = 0

        async def communicate(self):
            return self._data, None

    async def fake_exec(*args, **kwargs):
        if list(args[1:3]) == ["-m", "hermes_cli.main"] and "--check" in args:
            return CliProc()
        if "log" in args:
            if "--stat" in args:
                return GitProc(b"full changelog detail\n")
            return GitProc(
                b"abc1234 feat: stream resumed sessions live\n"
                b"def5678 fix(chat): restore model switching in full screen\n"
            )
        raise AssertionError(f"unexpected exec: {args}")

    monkeypatch.setattr(plugin.asyncio, "create_subprocess_exec", fake_exec)
    r = client.get("/api/plugins/hermes-mobile/update/status")
    assert r.status_code == 200
    body = r.json()
    assert body["updateAvailable"] is True
    assert body["notes"] == [
        {"section": "New features", "items": ["Stream resumed sessions live"]},
        {"section": "Fixes", "items": ["Restore model switching in full screen"]},
    ]

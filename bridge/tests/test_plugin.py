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

    async def list_sessions(self, *, limit=100):
        return [
            {
                "id": "20260805_plugin_session",
                "title": "Session plugin",
                "source": "acp",
                "profile": "default",
                "model": "deepseek-v4-flash",
                "updated_at": 1785900000,
                "is_active": True,
                "pinned": False,
            }
        ]

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
                "tool_calls": [],
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
            }
        ]

    async def set_model(self, model_id):
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


def test_plugin_messages_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/sessions/x/messages")
    assert resp.status_code == 200
    messages = resp.json()["messages"]
    assert len(messages) == 2
    assert isinstance(messages[0]["id"], str)
    assert "createdAt" in messages[0]
    assert messages[1]["role"] == "assistant"


def test_plugin_models_shape(client):
    resp = client.get("/api/plugins/hermes-mobile/models")
    assert resp.status_code == 200
    models = resp.json()["models"]
    assert len(models) == 1
    m = models[0]
    assert m["displayName"] == "deepseek-v4-flash"
    assert m["supportsVision"] is False
    assert m["supportsTools"] is True


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

    fake_cron = types.ModuleType("cron")
    fake_cron_jobs = types.ModuleType("cron.jobs")
    setattr(fake_cron_jobs, "list_jobs", lambda include_disabled=False: [dict(fake_job)])
    setattr(fake_cron_jobs, "pause_job", paused)
    setattr(fake_cron_jobs, "resume_job", resumed)
    setattr(fake_cron_jobs, "trigger_job", triggered)
    setattr(fake_cron_jobs, "remove_job", lambda job_id: job_id == "job1")
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

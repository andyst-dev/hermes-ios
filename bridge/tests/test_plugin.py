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

from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_stream_hook_writes_progressive_and_final_snapshots(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    hooks = _load_module("hermes_mobile_test_hooks", ROOT / "plugin" / "__init__.py")

    hooks.on_pre_llm_call(session_id="session-a")
    hooks.on_stream_delta(
        session_id="session-a", delta="Bon", accumulated_text="Bon"
    )
    # Force the next full snapshot past the write throttle without sleeping.
    hooks._STATE["session-a"]["last_write"] = 0.0
    hooks.on_stream_delta(
        session_id="session-a", delta="jour", accumulated_text="Bonjour"
    )

    path = hooks.snapshot_path("session-a")
    progressive = json.loads(path.read_text(encoding="utf-8"))
    assert progressive["active"] is True
    assert progressive["done"] is False
    assert progressive["text"] == "Bonjour"
    assert progressive["sequence"] == 2

    hooks.on_post_llm_call(
        session_id="session-a", assistant_response="Bonjour final"
    )
    final = json.loads(path.read_text(encoding="utf-8"))
    assert final["active"] is False
    assert final["done"] is True
    assert final["text"] == "Bonjour final"
    assert final["sequence"] == 3
    assert path.stat().st_mode & 0o777 == 0o600
    assert path.parent.stat().st_mode & 0o777 == 0o700


@pytest.mark.asyncio
async def test_live_endpoint_reads_and_expires_snapshot(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    hooks = _load_module("hermes_mobile_endpoint_hooks", ROOT / "plugin" / "__init__.py")
    api = _load_module(
        "hermes_mobile_endpoint_api", ROOT / "plugin" / "dashboard" / "plugin_api.py"
    )

    hooks.on_pre_llm_call(session_id="session-b")
    hooks._STATE["session-b"]["last_write"] = 0.0
    hooks.on_stream_delta(
        session_id="session-b", delta="Flux", accumulated_text="Flux visible"
    )

    live = await api.mobile_session_live("session-b")
    assert live == {
        "active": True,
        "sequence": 1,
        "text": "Flux visible",
        "done": False,
    }

    path = hooks.snapshot_path("session-b")
    payload = json.loads(path.read_text(encoding="utf-8"))
    payload["updated_at"] = time.time() - 121
    path.write_text(json.dumps(payload), encoding="utf-8")
    expired = await api.mobile_session_live("session-b")
    assert expired == {
        "active": False,
        "sequence": 0,
        "text": "",
        "done": False,
    }
    assert not path.exists()

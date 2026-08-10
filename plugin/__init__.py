"""Cross-process live assistant snapshots for Hermes Companion.

Hermes Desktop, gateways, and the standalone mobile dashboard can run in
separate processes. This observer hook mirrors only the already-sanitized
visible assistant text into a short-lived local snapshot so the dashboard can
relay an in-progress turn to the companion app. Hook failures are fail-open.
"""
from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from pathlib import Path
from typing import Any

_WRITE_INTERVAL_SECONDS = 0.05
_LOCK = threading.Lock()
_STATE: dict[str, dict[str, Any]] = {}


def _hermes_home() -> Path:
    configured = os.environ.get("HERMES_HOME", "").strip()
    return Path(configured).expanduser() if configured else Path.home() / ".hermes"


def _stream_dir() -> Path:
    path = _hermes_home() / "mobile-streams"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def snapshot_path(session_id: str) -> Path:
    digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return _stream_dir() / f"{digest}.json"


def _write_snapshot(
    session_id: str,
    *,
    sequence: int,
    text: str,
    active: bool,
    done: bool,
) -> None:
    payload = {
        "session_id": session_id,
        "sequence": sequence,
        "text": text,
        "active": active,
        "done": done,
        "updated_at": time.time(),
    }
    target = snapshot_path(session_id)
    temporary = target.with_name(
        f".{target.name}.{os.getpid()}.{threading.get_ident()}.tmp"
    )
    try:
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        temporary.chmod(0o600)
        os.replace(temporary, target)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass


def on_pre_llm_call(*, session_id: str = "", **_: Any) -> None:
    if not session_id:
        return
    now = time.monotonic()
    with _LOCK:
        _STATE[session_id] = {"sequence": 0, "text": "", "last_write": now}
        _write_snapshot(
            session_id,
            sequence=0,
            text="",
            active=True,
            done=False,
        )


def on_stream_delta(
    *,
    session_id: str = "",
    delta: str = "",
    accumulated_text: str = "",
    **_: Any,
) -> None:
    if not session_id or not delta:
        return
    now = time.monotonic()
    with _LOCK:
        state = _STATE.setdefault(
            session_id,
            {"sequence": 0, "text": "", "last_write": 0.0},
        )
        state["sequence"] = int(state["sequence"]) + 1
        state["text"] = accumulated_text or f"{state['text']}{delta}"
        if now - float(state["last_write"]) < _WRITE_INTERVAL_SECONDS:
            return
        state["last_write"] = now
        _write_snapshot(
            session_id,
            sequence=int(state["sequence"]),
            text=str(state["text"]),
            active=True,
            done=False,
        )


def on_post_llm_call(
    *,
    session_id: str = "",
    assistant_response: str = "",
    **_: Any,
) -> None:
    if not session_id:
        return
    with _LOCK:
        state = _STATE.pop(session_id, None) or {"sequence": 0, "text": ""}
        sequence = int(state["sequence"]) + 1
        final_text = assistant_response or str(state["text"])
        _write_snapshot(
            session_id,
            sequence=sequence,
            text=final_text,
            active=False,
            done=True,
        )


def register(ctx) -> None:
    ctx.register_hook("pre_llm_call", on_pre_llm_call)
    ctx.register_hook("on_stream_delta", on_stream_delta)
    ctx.register_hook("post_llm_call", on_post_llm_call)

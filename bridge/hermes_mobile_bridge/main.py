"""Mobile API consumed by the Hermes Companion iOS app, backed by the
official Hermes ACP server + dashboard REST API.

This module exposes :data:`mobile_router`, an ``APIRouter`` that can be
mounted by either:

- the standalone bridge (``python -m hermes_mobile_bridge.main``) under
  ``/api/mobile``, or
- the ``hermes-mobile`` dashboard plugin under
  ``/api/plugins/hermes-mobile``.

The same code path serves both; no Hermes core is patched either way.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import uuid
from typing import Any, Optional

from fastapi import APIRouter, FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from .acp_client import ACPExtEngine
from .dashboard import DashboardClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("hermes_mobile_bridge")

mobile_router = APIRouter()

# ---------------------------------------------------------------------------
# Runtime state (injectable for tests)
# ---------------------------------------------------------------------------

_engine: ACPExtEngine | None = None
_dashboard: DashboardClient | None = None


def _get_engine() -> ACPExtEngine:
    global _engine
    if _engine is None:
        _engine = ACPExtEngine(
            acp_bin=os.environ.get("HERMES_ACP_BIN", "hermes-acp"),
            model_id=os.environ.get("HERMES_MOBILE_MODEL"),
            provider=os.environ.get("HERMES_MOBILE_PROVIDER"),
        )
    return _engine

def _get_dashboard() -> DashboardClient:
    global _dashboard
    if _dashboard is None:
        _dashboard = DashboardClient()
    return _dashboard


def _reset_runtime_for_tests() -> None:
    global _engine, _dashboard
    _engine = None
    _dashboard = None


# ---------------------------------------------------------------------------
# Schemas (mobile contract)
# ---------------------------------------------------------------------------


class MobileChatRequest(BaseModel):
    text: str = Field(..., min_length=1)
    sessionID: Optional[str] = None
    attachments: Optional[list[dict[str, Any]]] = None
    profile: Optional[str] = None


class MobileNewChatRequest(BaseModel):
    profile: Optional[str] = None


class MobileStopRequest(BaseModel):
    sessionID: Optional[str] = None


class MobileReplyRequest(BaseModel):
    verdict: str


class MobileModelRequest(BaseModel):
    provider: Optional[str] = None
    model: str


class MobileRenameRequest(BaseModel):
    title: str


class MobileArchiveRequest(BaseModel):
    archived: bool = True


class MobilePinRequest(BaseModel):
    pinned: bool = True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _mobile_session_row(row: dict[str, Any]) -> dict[str, Any]:
    """Adapt a dashboard session row to the mobile shape."""
    sid = row.get("id") or row.get("session_id") or ""
    title = row.get("title") or row.get("name") or "Untitled"
    source = row.get("source") or "unknown"
    profile = row.get("profile") or "default"
    model = row.get("model") or ""
    updated = row.get("updated_at") or row.get("last_active") or row.get("started_at") or 0
    # The app shows a subtitle like "default · telegram · deepseek-v4-flash · 12 messages"
    message_count = row.get("message_count") or row.get("num_messages") or 0
    subtitle = f"{profile} · {source} · {model}".strip(" · ")
    if message_count:
        subtitle += f" · {message_count} messages"
    return {
        "id": sid,
        "title": title,
        "subtitle": subtitle,
        "updatedAt": _iso_ts(updated),
        # The iOS app's SessionStatus enum accepts idle|running|waitingApproval|
        # failed|completed — map the dashboard's is_active boolean to those.
        "status": "running" if row.get("is_active") else "idle",
        "pinned": bool(row.get("pinned")),
    }


def _iso_ts(ts: Any) -> str:
    """Best-effort ISO timestamp from a dashboard row (epoch int or iso str).

    The iOS app's ISO8601DateFormatter (.withInternetDateTime) only accepts
    ``Z`` as the UTC designator — never ``+00:00`` — so normalize to ``Z``.
    """
    if isinstance(ts, (int, float)) and ts > 0:
        import datetime

        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        return dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    if isinstance(ts, str):
        return ts.replace("+00:00", "Z")
    return ""


async def _sse(events: list[dict[str, Any]]) -> StreamingResponse:
    async def gen():
        for event in events:
            yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
            await asyncio.sleep(0)

    return StreamingResponse(gen(), media_type="text/event-stream")


# ---------------------------------------------------------------------------
# Health / capabilities
# ---------------------------------------------------------------------------


@mobile_router.get("/health")
async def mobile_health() -> dict[str, Any]:
    dash = await _get_dashboard().health()
    return {"ok": bool(dash.get("ok")), "version": "0.19.1", "auth_required": False}


@mobile_router.get("/capabilities")
async def mobile_capabilities() -> dict[str, Any]:
    try:
        sessions = await _get_dashboard().list_sessions(limit=1)
        has_sessions = True
    except Exception:
        has_sessions = False
    return {
        "streaming": True,
        "approvals": True,
        "files": True,
        "attachments": True,
        "sessions": has_sessions,
        "models": [],
    }


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------


@mobile_router.get("/sessions")
async def mobile_sessions(source: str | None = None) -> dict[str, Any]:
    rows = await _get_dashboard().list_sessions(limit=100, source=source)
    return {"sessions": [_mobile_session_row(r) for r in rows]}


@mobile_router.get("/sessions/{session_id}/messages")
async def mobile_session_messages(session_id: str) -> dict[str, Any]:
    try:
        raw = await _get_dashboard().get_session_messages(session_id)
    except Exception as exc:
        raise HTTPException(status_code=404, detail=f"Session not found: {exc}") from exc
    messages = []
    for m in raw:
        role = m.get("role")
        if role not in ("user", "assistant"):
            continue
        text = m.get("content") or m.get("text") or ""
        if isinstance(text, list):  # content blocks
            text = " ".join(
                b.get("text", "") for b in text if isinstance(b, dict) and b.get("type") == "text"
            )
        messages.append(
            {
                "id": str(m.get("id") or uuid.uuid4()),
                "role": role,
                "text": text,
                "toolCalls": _tool_calls_from_row(m),
                "createdAt": _iso_ts(m.get("created_at") or m.get("timestamp") or m.get("started_at")),
            }
        )
    return {"messages": messages}


def _tool_calls_from_row(m: dict[str, Any]) -> list[dict[str, Any]]:
    calls = []
    for tc in m.get("tool_calls") or []:
        # The iOS app's HermesToolCall requires name/status/summary; status
        # enum is queued|running|succeeded|failed|waitingApproval. The
        # dashboard rows carry raw tool_calls with 'name'/'arguments' and an
        # optional 'status' (or a command string in the 'command' field).
        name = tc.get("name") or tc.get("tool_name") or "tool"
        raw_status = str(tc.get("status") or "completed").lower()
        status = raw_status if raw_status in ("queued", "running", "succeeded", "failed", "waitingApproval") else "succeeded"
        arguments = tc.get("arguments") or tc.get("input") or ""
        command = tc.get("command") or (json.dumps(arguments)[:300] if arguments else "")
        calls.append(
            {
                "id": str(tc.get("id") or uuid.uuid4()),
                "name": name,
                "command": command,
                "status": status,
                "summary": name,
            }
        )
    return calls


@mobile_router.post("/new-chat")
async def mobile_new_chat(body: MobileNewChatRequest | None = None) -> dict[str, Any]:
    engine = _get_engine()
    hermes_id = await engine.new_session()
    return {"ok": True, "sessionID": hermes_id}


@mobile_router.post("/stop")
async def mobile_stop(body: MobileStopRequest | None = None) -> dict[str, Any]:
    engine = _get_engine()
    sid = (body.sessionID if body else None) or engine._active_hermes_session
    if sid:
        await engine.cancel(sid)
        return {"detail": "Stop requested"}
    return {"detail": "No running turn"}


@mobile_router.post("/sessions/{session_id}/rename")
async def mobile_rename(session_id: str, body: MobileRenameRequest) -> dict[str, Any]:
    try:
        await _get_dashboard().patch_session(session_id, {"title": body.title})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "title": body.title}


@mobile_router.post("/sessions/{session_id}/pin")
async def mobile_pin(session_id: str, body: MobilePinRequest | None = None) -> dict[str, Any]:
    pinned = body.pinned if body else True
    try:
        await _get_dashboard().patch_session(session_id, {"pinned": pinned})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "pinned": pinned}


@mobile_router.post("/sessions/{session_id}/archive")
async def mobile_archive(session_id: str, body: MobileArchiveRequest | None = None) -> dict[str, Any]:
    archived = body.archived if body else True
    try:
        await _get_dashboard().patch_session(session_id, {"archived": archived})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "archived": archived}


# ---------------------------------------------------------------------------
# Chat (SSE streaming via ACP)
# ---------------------------------------------------------------------------


@mobile_router.post("/chat")
async def mobile_chat(body: MobileChatRequest) -> StreamingResponse:
    engine = _get_engine()

    hermes_session_id = body.sessionID
    if hermes_session_id:
        hermes_session_id = await engine.resume_session(hermes_session_id)
    else:
        hermes_session_id = await engine.new_session()

    queue = engine.subscribe(hermes_session_id)

    async def stream_events():
        try:
            task = asyncio.create_task(engine.prompt(hermes_session_id, body.text))
            # Forward live events until the prompt RPC completes and the
            # queue is drained.
            while not task.done() or not queue.empty():
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=1.0)
                except asyncio.TimeoutError:
                    continue
                kind = item.get("kind")
                if kind == "delta":
                    yield f"data: {json.dumps({'type': 'delta', 'text': item.get('text', '')}, ensure_ascii=False)}\n\n"
                elif item.get("type") == "approval":
                    yield f"data: {json.dumps(item, ensure_ascii=False)}\n\n"
                elif kind == "tool":
                    yield f"data: {json.dumps({'type': 'tool', 'text': item.get('text', '')}, ensure_ascii=False)}\n\n"
            await task
            # Authoritative transcript from the dashboard.
            try:
                msgs = await _get_dashboard().get_session_messages(hermes_session_id)
            except Exception:
                msgs = []
            yield f"data: {json.dumps({'type': 'transcript', 'sessionID': hermes_session_id, 'messages': [_mobile_msg(m) for m in msgs]}, ensure_ascii=False)}\n\n"
            yield f"data: {json.dumps({'type': 'done'})}\n\n"
        except Exception as exc:
            logger.exception("chat stream failed")
            yield f"data: {json.dumps({'type': 'error', 'detail': str(exc)[:500]})}\n\n"
        finally:
            engine.unsubscribe(hermes_session_id)

    return StreamingResponse(stream_events(), media_type="text/event-stream")


def _mobile_msg(m: dict[str, Any]) -> dict[str, Any]:
    role = m.get("role")
    text = m.get("content") or m.get("text") or ""
    if isinstance(text, list):
        text = " ".join(b.get("text", "") for b in text if isinstance(b, dict) and b.get("type") == "text")
    return {
        "id": str(m.get("id") or uuid.uuid4()),
        "role": role,
        "text": text,
        "createdAt": _iso_ts(m.get("created_at") or m.get("timestamp") or m.get("started_at")),
        "toolCalls": _tool_calls_from_row(m),
    }


# ---------------------------------------------------------------------------
# Approvals
# ---------------------------------------------------------------------------


@mobile_router.post("/approvals/{approval_id}/reply")
async def mobile_approval_reply(approval_id: str, body: MobileReplyRequest) -> dict[str, Any]:
    if body.verdict not in ("once", "session", "always", "deny"):
        raise HTTPException(status_code=400, detail="verdict must be once|session|always|deny")
    engine = _get_engine()
    if not engine.resolve_approval(approval_id, body.verdict):
        raise HTTPException(status_code=404, detail="Unknown or expired approval id")
    return {"ok": True, "verdict": body.verdict}


# ---------------------------------------------------------------------------
# Models / files
# ---------------------------------------------------------------------------


@mobile_router.get("/models")
async def mobile_models() -> dict[str, Any]:
    try:
        rows = await _get_dashboard().model_options()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc
    models = []
    for r in rows:
        model_id = r.get("model_id") or r.get("id") or ""
        if not model_id:
            continue
        provider = r.get("provider") or model_id.split(":", 1)[0]
        # The iOS app's HermesModel requires displayName + supportsVision/
        # supportsTools; map from the dashboard row (or sensible defaults).
        supports_vision = bool(r.get("supports_vision") or r.get("vision") or "vision" in model_id.lower())
        models.append(
            {
                "id": model_id,
                "displayName": r.get("name") or r.get("display_name") or model_id,
                "provider": provider,
                "providerName": r.get("provider_name") or provider,
                "supportsVision": supports_vision,
                "supportsTools": True,
                "description": r.get("description") or "",
            }
        )
    return {"models": models, "providers": sorted({m["provider"] for m in models})}


@mobile_router.post("/model")
async def mobile_model_set(body: MobileModelRequest) -> dict[str, Any]:
    try:
        result = await _get_dashboard().set_model(body.model)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc
    return {"ok": True, "model": body.model, **result}


@mobile_router.get("/files")
async def mobile_files(path: str | None = None) -> dict[str, Any]:
    try:
        entries = await _get_dashboard().list_files(path)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc
    # The iOS app expects HermesFileArtifact rows: id(UUID), label, path, kind.
    artifacts = []
    for entry in entries:
        name = entry.get("name") or ""
        entry_path = entry.get("path") or ""
        mime = entry.get("mime_type") or ""
        artifacts.append(
            {
                "id": str(uuid.uuid4()),
                "label": name,
                "path": entry_path,
                "kind": "image" if mime.startswith("image/") else "text",
                "isDirectory": bool(entry.get("is_directory")),
                "size": entry.get("size"),
                "mtime": entry.get("mtime"),
            }
        )
    return {"files": artifacts, "path": path or ""}


@mobile_router.get("/files/read")
async def mobile_files_read(path: str) -> dict[str, Any]:
    try:
        result = await _get_dashboard().read_file(path)
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    # Dashboard returns {name, path, size, mime_type, data_url(base64)}; the
    # iOS app expects {name, content, truncated}.
    name = result.get("name") or os.path.basename(path)
    content = ""
    data_url = result.get("data_url") or ""
    if data_url.startswith("data:") and "base64," in data_url:
        import base64

        b64 = data_url.split("base64,", 1)[1]
        try:
            content = base64.b64decode(b64).decode("utf-8", errors="replace")
        except Exception:
            content = ""
    truncated = len(content) > 200_000
    if truncated:
        content = content[:200_000]
    return {"name": name, "content": content, "truncated": truncated}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def create_app() -> FastAPI:
    """Build the standalone FastAPI app mounting the mobile router."""
    application = FastAPI(title="Hermes Mobile Bridge", version="0.1.0")
    application.include_router(mobile_router, prefix="/api/mobile")
    return application


def main() -> None:
    import uvicorn

    host = os.environ.get("HERMES_MOBILE_BRIDGE_HOST", "127.0.0.1")
    port = int(os.environ.get("HERMES_MOBILE_BRIDGE_PORT", "8766"))
    uvicorn.run(create_app(), host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()

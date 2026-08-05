"""Hermes Mobile dashboard plugin — backend API routes.

Mounted at ``/api/plugins/hermes-mobile/`` by the dashboard plugin system
(``web_server._mount_plugin_api_routes``). Serves the mobile API consumed by
the Hermes Companion iOS app: live SSE chat streaming and dangerous-command
approvals over the official Agent Client Protocol (``hermes-acp``), plus
sessions/files/models proxied from the dashboard REST API.

No Hermes core is patched. The plugin talks to the same official surfaces
Zed/VS Code use: the ACP server for chat/approvals and the dashboard REST API
for the rest. This file is intentionally self-contained (the dashboard's venv
has fastapi/httpx/agent-client-protocol already) so installing the plugin is
the only step needed.

Security: plugin HTTP routes go through the dashboard's session-token auth
middleware like core API routes, so every ``/api/plugins/...`` request must
present the session bearer token.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import secrets
import time
import uuid
from typing import Any, Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

logger = logging.getLogger("hermes_mobile_plugin")

router = APIRouter()

# ---------------------------------------------------------------------------
# ACP engine (official agent-client-protocol SDK — ships with Hermes)
# ---------------------------------------------------------------------------

try:
    from acp.client.connection import ClientSideConnection
    from acp.schema import ClientCapabilities, Implementation, TextContentBlock
    from acp.transports import spawn_stdio_transport
except ImportError as exc:  # pragma: no cover
    raise RuntimeError(
        "hermes-mobile plugin requires agent-client-protocol "
        "(hermes ACP extra): cd ~/.hermes/hermes-agent && uv pip install -e '.[acp]'"
    ) from exc


class _PhoneClient:
    """ACP Client side (what the server calls on us)."""

    def __init__(self, engine: "PluginACPEngine") -> None:
        self.engine = engine

    async def session_update(self, session_id: str, update: Any, **kwargs: Any) -> None:
        await self.engine._on_session_update(session_id, update)

    async def request_permission(
        self, options: list[Any], session_id: str, tool_call: Any, **kwargs: Any
    ) -> dict[str, Any]:
        return await self.engine._on_request_permission(options, session_id, tool_call)

    def on_connect(self, conn: Any) -> None:
        return None


class PluginACPEngine:
    """Owns one ``hermes-acp`` subprocess and the active ACP session(s)."""

    def __init__(self) -> None:
        self.acp_bin = os.environ.get("HERMES_ACP_BIN", "hermes-acp")
        self._model_id = os.environ.get("HERMES_MOBILE_MODEL")
        self._provider = os.environ.get("HERMES_MOBILE_PROVIDER")
        self._cwd = os.path.expanduser("~")

        self._transport: Any = None
        self._conn: ClientSideConnection | None = None
        self._proc: Any = None
        self._session_map: dict[str, str] = {}
        self._reverse_map: dict[str, str] = {}
        self._active_hermes_session: str | None = None
        self._turn_queues: dict[str, "asyncio.Queue[dict]"] = {}
        self._pending_permissions: dict[str, asyncio.Future] = {}
        self._approval_map: dict[str, str] = {}

    async def start(self) -> None:
        if self._conn is not None:
            return
        env = {k: v for k, v in os.environ.items() if k in ("HOME", "PATH", "USER", "SHELL", "TERM", "LOGNAME")}
        env.setdefault("HERMES_ACP_SKIP_CONFIGURED_MCP", "1")
        if self._provider:
            env["HERMES_PROVIDER"] = self._provider
        if self._model_id:
            env["HERMES_MODEL"] = self._model_id

        self._transport = spawn_stdio_transport(self.acp_bin, env=env, cwd=self._cwd)
        self._reader, self._writer, self._proc = await self._transport.__aenter__()
        client = _PhoneClient(self)
        self._conn = ClientSideConnection(client, self._writer, self._reader, use_unstable_protocol=True)
        await self._conn.initialize(
            protocol_version=1,
            client_capabilities=ClientCapabilities(),
            client_info=Implementation(name="hermes-mobile-plugin", version="1.0.0"),
        )
        logger.info("hermes-acp handshake complete (pid=%s)", self._proc.pid)

    async def stop(self) -> None:
        if self._transport is not None:
            try:
                await self._transport.__aexit__(None, None, None)
            except Exception:
                logger.debug("acp transport close failed", exc_info=True)
            self._transport = None
        self._conn = None
        self._proc = None

    async def new_session(self, hermes_session_id: str | None = None) -> str:
        await self.start()
        assert self._conn is not None
        resp = await self._conn.new_session(cwd=self._cwd, mcp_servers=[])
        acp_id = resp.session_id
        hermes_id = self._hermes_id_from_meta(resp) or hermes_session_id or acp_id
        self._session_map[hermes_id] = acp_id
        self._reverse_map[acp_id] = hermes_id
        self._active_hermes_session = hermes_id
        if self._model_id:
            await self._set_session_model(acp_id, self._model_id)
        return hermes_id

    async def resume_session(self, hermes_session_id: str) -> str:
        await self.start()
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is None:
            return await self.new_session(hermes_session_id)
        assert self._conn is not None
        await self._conn.resume_session(cwd=self._cwd, session_id=acp_id, mcp_servers=[])
        self._active_hermes_session = hermes_session_id
        return hermes_session_id

    async def _set_session_model(self, acp_id: str, model_id: str) -> None:
        try:
            conn = getattr(self._conn, "_conn", None)
            if conn is None:
                return
            resolved = model_id
            if ":" not in resolved and self._provider:
                resolved = f"{self._provider}:{resolved}"
            await conn.send_request(
                "session/set_model",
                {"sessionId": acp_id, "modelId": resolved},
            )
        except Exception:
            logger.warning("set_session_model(%s) failed", model_id, exc_info=True)

    def subscribe(self, hermes_session_id: str) -> "asyncio.Queue[dict]":
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is None:
            raise HTTPException(status_code=400, detail=f"no acp session for {hermes_session_id}")
        queue: asyncio.Queue[dict] = asyncio.Queue()
        self._turn_queues[acp_id] = queue
        return queue

    def unsubscribe(self, hermes_session_id: str) -> None:
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is not None:
            self._turn_queues.pop(acp_id, None)

    async def prompt(self, hermes_session_id: str, text: str) -> dict:
        await self.start()
        assert self._conn is not None
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is None:
            hermes_session_id = await self.new_session(hermes_session_id)
            acp_id = self._session_map[hermes_session_id]
        self._active_hermes_session = hermes_session_id
        result = await self._conn.prompt(
            prompt=[TextContentBlock(type="text", text=text)],
            session_id=acp_id,
        )
        return result.model_dump() if result is not None else {}

    async def cancel(self, hermes_session_id: str) -> None:
        if self._conn is None:
            return
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is None:
            return
        try:
            await self._conn.cancel(session_id=acp_id)
        except Exception:
            logger.debug("acp cancel failed", exc_info=True)

    async def _on_request_permission(
        self, options: list[Any], session_id: str, tool_call: Any
    ) -> dict[str, Any]:
        option_ids = [getattr(o, "option_id", None) for o in options]
        description = self._tool_call_description(tool_call)
        approval_id = str(uuid.uuid4())
        self._approval_map[approval_id] = session_id

        queue = self._turn_queues.get(session_id)
        if queue is not None:
            await queue.put(
                {
                    "type": "approval",
                    "id": approval_id,
                    "command": description,
                    "description": description,
                }
            )

        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending_permissions[session_id] = future
        try:
            verdict = await asyncio.wait_for(future, timeout=600)
        except asyncio.TimeoutError:
            verdict = "deny"  # fail closed
        finally:
            self._pending_permissions.pop(session_id, None)
            self._approval_map.pop(approval_id, None)

        _VERDICT_TO_OPTION = {
            "once": "allow_once",
            "session": "allow_session",
            "always": "allow_always",
            "deny": "deny",
        }
        option = _VERDICT_TO_OPTION.get(verdict, verdict)
        if option not in option_ids:
            option = "deny" if "deny" in option_ids else option_ids[0]
        if option == "deny":
            return {"outcome": {"outcome": "cancelled"}}
        return {"outcome": {"outcome": "selected", "optionId": option}}

    def resolve_approval(self, approval_id: str, verdict: str) -> bool:
        acp_uuid = self._approval_map.pop(approval_id, None)
        if acp_uuid is None:
            return False
        future = self._pending_permissions.get(acp_uuid)
        if future is None or future.done():
            return False
        future.set_result(verdict)
        return True

    @staticmethod
    def _tool_call_description(tool_call: Any) -> str:
        raw_input = getattr(tool_call, "raw_input", None)
        if isinstance(raw_input, dict):
            command = raw_input.get("command") or ""
            description = raw_input.get("description") or ""
            if description and command:
                return f"{description}\n$ {command}"
            if description:
                return description
            if command:
                return command
        content = getattr(tool_call, "content", None) or []
        for block in content:
            inner = getattr(block, "content", None)
            text = getattr(inner, "text", None)
            if text:
                return text
        title = getattr(tool_call, "title", None)
        if title:
            return title
        return str(tool_call)[:300]

    async def _on_session_update(self, session_id: str, update: Any) -> None:
        queue = self._turn_queues.get(session_id)
        if queue is None:
            return
        kind = getattr(update, "session_update", None)
        if kind == "usage_update":
            return
        content = getattr(update, "content", None)
        text = getattr(content, "text", None) if content is not None else None
        if isinstance(text, str) and text:
            await queue.put({"kind": "delta", "text": text})
        elif kind in ("tool_call_start", "tool_call_progress"):
            await queue.put({"kind": "tool", "text": str(update)[:300]})

    @staticmethod
    def _hermes_id_from_meta(resp: Any) -> str | None:
        try:
            meta = getattr(resp, "field_meta", None) or {}
            provenance = meta.get("hermes", {}).get("sessionProvenance", {})
            return provenance.get("currentHermesSessionId")
        except Exception:
            return None


# ---------------------------------------------------------------------------
# Dashboard proxy (official REST API)
# ---------------------------------------------------------------------------


class _DashboardProxy:
    """Thin proxy to the dashboard REST API (the plugin runs inside it)."""

    def __init__(self) -> None:
        import httpx

        self._client = httpx.AsyncClient(timeout=30.0)
        self._base = os.environ.get("HERMES_DASHBOARD_URL", "http://127.0.0.1:8765").rstrip("/")
        self._token = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self._token:
            headers["X-Hermes-Session-Token"] = self._token
        return headers

    async def health(self) -> dict[str, Any]:
        try:
            resp = await self._client.get(f"{self._base}/api/health", headers=self._headers())
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            return {"ok": False, "error": str(exc)[:200]}

    async def list_sessions(self, *, limit: int = 100) -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self._base}/api/sessions",
            params={"limit": limit, "archived": "exclude"},
            headers=self._headers(),
        )
        resp.raise_for_status()
        return resp.json().get("sessions", [])

    async def get_session_messages(self, session_id: str) -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self._base}/api/sessions/{session_id}/messages", headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json().get("messages", [])

    async def patch_session(self, session_id: str, patch: dict[str, Any]) -> dict[str, Any]:
        resp = await self._client.patch(
            f"{self._base}/api/sessions/{session_id}", json=patch, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

    async def list_files(self, path: str | None = None) -> list[dict[str, Any]]:
        params = {}
        if path:
            params["path"] = os.path.expanduser(path) if not path.startswith("/") else path
        resp = await self._client.get(f"{self._base}/api/files", params=params, headers=self._headers())
        resp.raise_for_status()
        payload = resp.json()
        # Dashboard shape: {"path", "parent", "entries": [{"name", "path", "is_directory", ...}]}
        return payload.get("entries", [])

    async def read_file(self, path: str) -> dict[str, Any]:
        absolute = path if path.startswith("/") else os.path.join(os.path.expanduser("~"), path)
        resp = await self._client.get(
            f"{self._base}/api/files/read", params={"path": absolute}, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

    async def model_options(self) -> list[dict[str, Any]]:
        resp = await self._client.get(f"{self._base}/api/model/options", headers=self._headers())
        resp.raise_for_status()
        payload = resp.json()
        # Dashboard shape: {"providers": [{"slug", "name", "is_current", "models": [...]}]}
        rows = []
        for provider in payload.get("providers", []):
            slug = provider.get("slug") or ""
            name = provider.get("name") or slug
            for model_id in provider.get("models", []):
                rows.append(
                    {
                        "model_id": model_id,
                        "provider": slug,
                        "provider_name": name,
                        "name": model_id.split("/", 1)[-1],
                    }
                )
        return rows

    async def set_model(self, model_id: str) -> dict[str, Any]:
        # Dashboard POST /api/model/set expects ModelAssignment:
        # {"scope": "main", "provider": "...", "model": "..."}
        provider, _, model = model_id.partition("/")
        resp = await self._client.post(
            f"{self._base}/api/model/set",
            json={"scope": "main", "provider": provider, "model": model or model_id},
            headers=self._headers(),
        )
        resp.raise_for_status()
        return resp.json()

    # -- reasoning effort ------------------------------------------------

    EFFORT_OPTIONS = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    async def get_reasoning_effort(self) -> dict[str, Any]:
        """Read agent.reasoning_effort from the dashboard config."""
        resp = await self._client.get(
            f"{self._base}/api/config", headers=self._headers()
        )
        resp.raise_for_status()
        config = resp.json()
        agent = config.get("agent") or {}
        current = agent.get("reasoning_effort") or ""
        return {
            "effort": current,
            "options": list(self.EFFORT_OPTIONS),
        }

    async def set_reasoning_effort(self, effort: str) -> dict[str, Any]:
        """Persist agent.reasoning_effort (deep-merge keeps everything else)."""
        if effort not in self.EFFORT_OPTIONS:
            raise ValueError(f"invalid effort: {effort}")
        resp = await self._client.put(
            f"{self._base}/api/config",
            json={"config": {"agent": {"reasoning_effort": effort}}},
            headers=self._headers(),
        )
        resp.raise_for_status()
        return {"ok": True, "effort": effort}


_engine: PluginACPEngine | None = None
_dashboard: _DashboardProxy | None = None


def _get_engine() -> PluginACPEngine:
    global _engine
    if _engine is None:
        _engine = PluginACPEngine()
    return _engine


def _get_dashboard() -> _DashboardProxy:
    global _dashboard
    if _dashboard is None:
        _dashboard = _DashboardProxy()
    return _dashboard


# ---------------------------------------------------------------------------
# Mobile contract helpers (identical shapes to the standalone bridge)
# ---------------------------------------------------------------------------


def _iso_ts(ts: Any) -> str:
    if isinstance(ts, (int, float)) and ts > 0:
        import datetime

        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        return dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    if isinstance(ts, str):
        return ts.replace("+00:00", "Z")
    return ""


def _mobile_session_row(row: dict[str, Any]) -> dict[str, Any]:
    sid = row.get("id") or row.get("session_id") or ""
    title = row.get("title") or row.get("name") or "Untitled"
    source = row.get("source") or "unknown"
    profile = row.get("profile") or "default"
    model = row.get("model") or ""
    updated = row.get("updated_at") or row.get("last_active") or row.get("started_at") or 0
    message_count = row.get("message_count") or row.get("num_messages") or 0
    subtitle = f"{profile} · {source} · {model}".strip(" · ")
    if message_count:
        subtitle += f" · {message_count} messages"
    return {
        "id": sid,
        "title": title,
        "subtitle": subtitle,
        "updatedAt": _iso_ts(updated),
        "status": "running" if row.get("is_active") else "idle",
        "pinned": bool(row.get("pinned")),
    }


def _tool_calls_from_row(m: dict[str, Any]) -> list[dict[str, Any]]:
    calls = []
    for tc in m.get("tool_calls") or []:
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
# Schemas
# ---------------------------------------------------------------------------


class _ChatRequest(BaseModel):
    text: str = Field(..., min_length=1)
    sessionID: Optional[str] = None
    attachments: Optional[list[dict[str, Any]]] = None


class _StopRequest(BaseModel):
    sessionID: Optional[str] = None


class _ReplyRequest(BaseModel):
    verdict: str


class _ModelRequest(BaseModel):
    provider: Optional[str] = None
    model: str


class _EffortRequest(BaseModel):
    effort: str


class _RenameRequest(BaseModel):
    title: str


class _ArchiveRequest(BaseModel):
    archived: bool = True


class _PinRequest(BaseModel):
    pinned: bool = True


# ---------------------------------------------------------------------------
# Routes (mounted under /api/plugins/hermes-mobile/)
# ---------------------------------------------------------------------------


@router.get("/health")
async def mobile_health() -> dict[str, Any]:
    dash = await _get_dashboard().health()
    return {"ok": bool(dash.get("ok")), "version": "1.0.0", "auth_required": False}


@router.get("/capabilities")
async def mobile_capabilities() -> dict[str, Any]:
    try:
        await _get_dashboard().list_sessions(limit=1)
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


@router.get("/sessions")
async def mobile_sessions() -> dict[str, Any]:
    rows = await _get_dashboard().list_sessions(limit=100)
    return {"sessions": [_mobile_session_row(r) for r in rows]}


@router.get("/sessions/{session_id}/messages")
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
        if isinstance(text, list):
            text = " ".join(b.get("text", "") for b in text if isinstance(b, dict) and b.get("type") == "text")
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


@router.post("/new-chat")
async def mobile_new_chat() -> dict[str, Any]:
    hermes_id = await _get_engine().new_session()
    return {"ok": True, "sessionID": hermes_id}


@router.post("/stop")
async def mobile_stop(body: Optional[_StopRequest] = None) -> dict[str, Any]:
    engine = _get_engine()
    sid = (body.sessionID if body else None) or engine._active_hermes_session
    if sid:
        await engine.cancel(sid)
        return {"detail": "Stop requested"}
    return {"detail": "No running turn"}


@router.post("/sessions/{session_id}/rename")
async def mobile_rename(session_id: str, body: _RenameRequest) -> dict[str, Any]:
    try:
        await _get_dashboard().patch_session(session_id, {"title": body.title})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "title": body.title}


@router.post("/sessions/{session_id}/pin")
async def mobile_pin(session_id: str, body: Optional[_PinRequest] = None) -> dict[str, Any]:
    pinned = body.pinned if body else True
    try:
        await _get_dashboard().patch_session(session_id, {"pinned": pinned})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "pinned": pinned}


@router.post("/sessions/{session_id}/archive")
async def mobile_archive(session_id: str, body: Optional[_ArchiveRequest] = None) -> dict[str, Any]:
    archived = body.archived if body else True
    try:
        await _get_dashboard().patch_session(session_id, {"archived": archived})
    except Exception as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, "archived": archived}


@router.post("/chat")
async def mobile_chat(body: _ChatRequest) -> StreamingResponse:
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


@router.post("/approvals/{approval_id}/reply")
async def mobile_approval_reply(approval_id: str, body: _ReplyRequest) -> dict[str, Any]:
    if body.verdict not in ("once", "session", "always", "deny"):
        raise HTTPException(status_code=400, detail="verdict must be once|session|always|deny")
    if not _get_engine().resolve_approval(approval_id, body.verdict):
        raise HTTPException(status_code=404, detail="Unknown or expired approval id")
    return {"ok": True, "verdict": body.verdict}


@router.get("/models")
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


@router.post("/model")
async def mobile_model_set(body: _ModelRequest) -> dict[str, Any]:
    try:
        result = await _get_dashboard().set_model(body.model)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc
    return {"ok": True, "model": body.model, **result}


@router.get("/model/effort")
async def mobile_model_effort_get() -> dict[str, Any]:
    try:
        return await _get_dashboard().get_reasoning_effort()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc


@router.post("/model/effort")
async def mobile_model_effort_set(body: _EffortRequest) -> dict[str, Any]:
    try:
        return await _get_dashboard().set_reasoning_effort(body.effort)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc


@router.get("/files")
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
        is_dir = bool(entry.get("is_directory"))
        mime = entry.get("mime_type") or ""
        kind = "image" if mime.startswith("image/") else "text"
        artifacts.append(
            {
                "id": str(uuid.uuid4()),
                "label": name,
                "path": entry_path,
                "kind": kind,
                "isDirectory": is_dir,
                "size": entry.get("size"),
                "mtime": entry.get("mtime"),
            }
        )
    return {"files": artifacts, "path": path or ""}


@router.get("/files/read")
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
# Attachments (photo from the iOS picker → stored on the desktop)
# ---------------------------------------------------------------------------

_ATTACH_DIR = os.path.expanduser("~/.hermes/mobile-attachments")
_ATTACH_MAX_BYTES = 20 * 1024 * 1024


@router.post("/attachments")
async def mobile_attachments_upload(
    file: "UploadFile" = File(...),
) -> dict[str, Any]:
    """Multipart upload stored under ~/.hermes/mobile-attachments/ (20 MB cap)."""
    os.makedirs(_ATTACH_DIR, exist_ok=True)
    data = await file.read()
    if len(data) > _ATTACH_MAX_BYTES:
        raise HTTPException(status_code=413, detail="Attachment exceeds 20 MB")
    safe_name = os.path.basename(file.filename or "attachment.bin")
    target = os.path.join(_ATTACH_DIR, f"{uuid.uuid4().hex[:8]}-{safe_name}")
    with open(target, "wb") as fh:
        fh.write(data)
    rel = os.path.relpath(target, os.path.expanduser("~"))
    return {"path": rel}


@router.post("/files/attach")
async def mobile_files_attach(path: str) -> dict[str, Any]:
    """Attach an existing Desktop-managed file without re-uploading."""
    import mimetypes

    home = os.path.expanduser("~")
    full = os.path.normpath(os.path.join(home, path))
    if not full.startswith(home + os.sep) or os.path.commonpath([home, full]) != home:
        raise HTTPException(status_code=400, detail="Path traversal rejected")
    if not os.path.isfile(full):
        raise HTTPException(status_code=404, detail="File not found")
    if os.path.basename(full) == ".env":
        raise HTTPException(status_code=403, detail="Sensitive file rejected")
    size = os.path.getsize(full)
    if size > _ATTACH_MAX_BYTES:
        raise HTTPException(status_code=413, detail="File exceeds 20 MB")
    mime, _ = mimetypes.guess_type(full)
    if mime and not mime.startswith("image/"):
        raise HTTPException(status_code=415, detail="Only images can be attached")
    return {
        "id": str(uuid.uuid4()),
        "name": os.path.basename(full),
        "path": os.path.relpath(full, home),
        "mimeType": mime or "application/octet-stream",
        "sizeBytes": size,
    }


# ---------------------------------------------------------------------------
# QR pairing (onboarding: scan a Desktop QR, get the session token)
# ---------------------------------------------------------------------------

_PAIRING_TTL_SECONDS = 120
_pairing_codes: dict[str, dict[str, Any]] = {}


def _clean_pairings() -> None:
    now = time.time()
    for code, value in list(_pairing_codes.items()):
        if float(value.get("expires_at") or 0) <= now:
            _pairing_codes.pop(code, None)


def _dashboard_session_token() -> str:
    """The dashboard's own session token — the plugin runs inside it."""
    try:
        from hermes_cli import web_server as _ws

        return getattr(_ws, "_SESSION_TOKEN", "") or os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
    except Exception:
        return os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")


@router.get("/pairing")
async def mobile_pairing(profile: Optional[str] = None) -> dict[str, Any]:
    """Generate a one-time pairing QR payload (120 s TTL).

    The QR embeds the dashboard session token directly (the dashboard is
    already authenticated when the QR is generated), so the iOS app can
    connect without a public unauthenticated ``/pair`` endpoint — the
    dashboard's auth middleware protects every ``/api/plugins/*`` route.
    """
    _clean_pairings()
    code = secrets.token_urlsafe(18)
    active_profile = (profile or os.environ.get("HERMES_PROFILE") or "default").strip() or "default"
    base_url = os.environ.get("HERMES_MOBILE_PUBLIC_URL", "http://127.0.0.1:8765").rstrip("/")
    token = _dashboard_session_token()
    _pairing_codes[code] = {
        "profile": active_profile,
        "base_url": base_url,
        "expires_at": time.time() + _PAIRING_TTL_SECONDS,
    }
    qr_payload = {
        "type": "hermes-mobile-pairing",
        "url": base_url,
        "profile": active_profile,
        # `code` kept for backward compat with the standalone bridge flow;
        # `token` lets the app connect straight away.
        "code": code,
        "token": token,
    }
    return {
        "url": base_url,
        "profile": active_profile,
        "code": code,
        "token": token,
        "expiresAt": _iso_ts(time.time() + _PAIRING_TTL_SECONDS),
        "qrText": json.dumps(qr_payload, separators=(",", ":")),
    }


class _PairRequest(BaseModel):
    code: str
    deviceName: Optional[str] = "iPhone"


@router.post("/pair")
async def mobile_pair(body: _PairRequest) -> dict[str, Any]:
    """Exchange a scanned one-time code for the dashboard session token."""
    _clean_pairings()
    code = (body.code or "").strip()
    pairing = _pairing_codes.pop(code, None)
    if not pairing:
        raise HTTPException(status_code=404, detail="Pairing code expired")
    token = _dashboard_session_token()
    if not token:
        raise HTTPException(status_code=500, detail="No dashboard session token available")
    return {
        "ok": True,
        "url": pairing["base_url"],
        "profile": pairing["profile"],
        "token": token,
    }

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
import atexit
import base64
import json
import logging
import os
import re
import secrets
import shutil
import time
import uuid
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from urllib.parse import urlparse

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
        self._approval_map: dict[str, dict[str, str]] = {}
        self._active_turn: asyncio.Task | None = None
        self._turn_session: str | None = None

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
        """Resume an existing Hermes session by its Hermes-side id.

        Sessions this plugin created in this process are in ``_session_map``
        and resume by their ACP uuid. An UNKNOWN id does not mean a fresh
        conversation though: the ACP server restores previously persisted ACP
        sessions from the shared SessionDB by this very id
        (``acp_adapter/session.py::_restore``), so after a dashboard restart
        the same conversation is still resumable. Try ``session/resume`` with
        the hermes id itself first, and only adopt a fresh session when the
        server really minted one (its returned hermes id differs from the
        requested one - e.g. a conversation that was never ACP-persisted,
        like one created on Desktop/Telegram).
        """
        await self.start()
        assert self._conn is not None
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is not None:
            await self._conn.resume_session(cwd=self._cwd, session_id=acp_id, mcp_servers=[])
            self._active_hermes_session = hermes_session_id
            return hermes_session_id

        resp = await self._conn.resume_session(cwd=self._cwd, session_id=hermes_session_id, mcp_servers=[])
        restored = self._hermes_id_from_meta(resp)
        if restored == hermes_session_id:
            # The server restored the conversation from SessionDB under the
            # requested id - notifications will carry this id, so map it to
            # itself (notifications arrive keyed by the hermes id).
            self._session_map[hermes_session_id] = hermes_session_id
            self._reverse_map[hermes_session_id] = hermes_session_id
            self._active_hermes_session = hermes_session_id
            return hermes_session_id

        # The server could not restore that conversation and created a fresh
        # session instead - adopt it so the rest of the turn stays coherent.
        new_id = restored or hermes_session_id
        self._session_map[new_id] = new_id
        self._reverse_map[new_id] = new_id
        self._active_hermes_session = new_id
        return new_id

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

    async def cancel_active_turn(self) -> None:
        """Abort any turn still in flight on the shared ACP connection.

        The SDK supports ONE in-flight prompt per connection: if the app is
        relaunched mid-turn (the old stream dies but the server turn keeps
        running) and a new prompt is sent, the two prompts wedge the
        connection forever — the server turn never finishes and the new one
        never starts. Before starting a fresh turn, resolve pending
        approvals as denied (so a tool call blocked on permission unblocks)
        and cancel the old prompt task.
        """
        if self._active_turn is None:
            return
        # Unblock any tool call waiting on a phone approval verdict.
        for session_id in list(self._pending_permissions):
            future = self._pending_permissions[session_id]
            if not future.done():
                future.set_result("deny")
        if self._conn is not None and self._turn_session is not None:
            acp_id = self._session_map.get(self._turn_session)
            if acp_id is not None:
                try:
                    await self._conn.cancel(session_id=acp_id)
                except Exception:
                    logger.debug("acp cancel of stale turn failed", exc_info=True)
        task = self._active_turn
        try:
            await asyncio.wait_for(task, timeout=10)
        except asyncio.TimeoutError:
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        except Exception:
            pass
        if self._active_turn is task:
            self._active_turn = None
            self._turn_session = None

    async def _on_request_permission(
        self, options: list[Any], session_id: str, tool_call: Any
    ) -> dict[str, Any]:
        option_ids = [getattr(o, "option_id", None) for o in options]
        description = self._tool_call_description(tool_call)
        approval_id = str(uuid.uuid4())
        self._approval_map[approval_id] = {
            "session_id": session_id,
            "command": description,
        }

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
            verdict = await asyncio.wait_for(future, timeout=60)
        except asyncio.TimeoutError:
            verdict = "deny"  # fail closed — never let a turn wedge forever
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
        details = self._approval_map.pop(approval_id, None)
        if details is None:
            return False
        acp_uuid = details["session_id"]
        future = self._pending_permissions.get(acp_uuid)
        if future is None or future.done():
            return False
        future.set_result(verdict)
        return True

    def pending_approvals(self) -> dict[str, dict[str, str]]:
        """Snapshot of approvals waiting for a phone verdict (for push/alert
        polling). Keys are approval ids; values hold the session id and the
        human-readable command that triggered the permission request."""
        return {k: dict(v) for k, v in self._approval_map.items()}

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
        if kind == "agent_thought_chunk" and isinstance(text, str) and text:
            # Thinking/reasoning deltas must NOT be streamed as answer text.
            # ACP separates them (agent_thought_chunk vs agent_message_chunk);
            # forward them as a dedicated event so clients can render a
            # collapsible thinking block instead of polluting the reply.
            await queue.put({"kind": "thinking", "text": text})
        elif isinstance(text, str) and text:
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

    async def list_sessions(self, *, limit: int = 100, archived: str = "exclude") -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self._base}/api/sessions",
            params={"limit": limit, "archived": archived},
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
    raw_source = (row.get("source") or "unknown").lower()
    # ACP sessions (created through the mobile plugin/bridge) read as
    # "mobile" for the user — the wire source stays what the DB says.
    source = "mobile" if raw_source == "acp" else raw_source
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
        "source": source,
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
    msg = {
        "id": str(m.get("id") or uuid.uuid4()),
        "role": role,
        "text": text,
        "createdAt": _iso_ts(m.get("created_at") or m.get("timestamp") or m.get("started_at")),
        "toolCalls": _tool_calls_from_row(m),
    }
    # Desktop parity: persisted reasoning travels in its own field so the
    # app can show the collapsible thinking pane even after the turn.
    reasoning = m.get("reasoning_content") or m.get("reasoning")
    if isinstance(reasoning, str) and reasoning.strip():
        msg["thinking"] = reasoning
    return msg


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
async def mobile_sessions(archived: str = "exclude") -> dict[str, Any]:
    rows = await _get_dashboard().list_sessions(limit=100, archived=archived)
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
        messages.append(_mobile_msg(m))
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
    # One in-flight prompt per ACP connection: abort any turn left running
    # by a previous (possibly relaunched) client before starting a new one,
    # or the two prompts wedge the connection forever.
    await engine.cancel_active_turn()
    hermes_session_id = body.sessionID
    if hermes_session_id:
        hermes_session_id = await engine.resume_session(hermes_session_id)
    else:
        hermes_session_id = await engine.new_session()

    queue = engine.subscribe(hermes_session_id)

    async def stream_events():
        task: asyncio.Task | None = None
        try:
            task = asyncio.create_task(engine.prompt(hermes_session_id, body.text))
            engine._active_turn = task
            engine._turn_session = hermes_session_id
            while not task.done() or not queue.empty():
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=1.0)
                except asyncio.TimeoutError:
                    continue
                kind = item.get("kind")
                if kind == "delta":
                    yield f"data: {json.dumps({'type': 'delta', 'text': item.get('text', '')}, ensure_ascii=False)}\n\n"
                elif kind == "thinking":
                    yield f"data: {json.dumps({'type': 'thinking', 'text': item.get('text', '')}, ensure_ascii=False)}\n\n"
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
            # Only clear the active-turn marker when the prompt really
            # finished. If the CLIENT closed the stream mid-turn, the server
            # turn keeps running and must stay cancelable by the next /chat.
            if task is not None and engine._active_turn is task and task.done():
                engine._active_turn = None
                engine._turn_session = None

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
    # Prefer the active remote tunnel URL (iPhone outside the LAN), then the
    # explicit public URL override, then the localhost default (simulator).
    base_url = _tunnel_url or os.environ.get(
        "HERMES_MOBILE_PUBLIC_URL", "http://127.0.0.1:8765"
    ).rstrip("/")
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


# ---------------------------------------------------------------------------
# Remote tunnel (Cloudflare quick tunnel / ngrok) — outbound HTTPS, no VPN.
#
# Lets the iPhone reach the dashboard from outside the LAN without Tailscale
# or port-forwarding: the dashboard opens an OUTBOUND HTTPS connection to
# cloudflared/ngrok, which gives back a public URL. The iOS app connects to
# that URL; the dashboard session-token auth still protects every route.
# ---------------------------------------------------------------------------

_TUNNEL_URL_RE = re.compile(
    r"https://[a-z0-9-]+\.(?:trycloudflare\.com|ngrok-free\.app|ngrok\.app|ngrok\.io)"
)

_tunnel_proc: Optional["asyncio.subprocess.Process"] = None
_tunnel_proxy: Optional[_TunnelProxy] = None
_tunnel_url: str = ""
_tunnel_provider: str = ""
_tunnel_error: str = ""


def _find_tunnel_bin() -> Optional[str]:
    """cloudflared preferred (quick tunnels need no account); ngrok fallback."""
    override = os.environ.get("HERMES_MOBILE_TUNNEL_BIN", "").strip()
    if override:
        return override if shutil.which(override) else None
    for name in ("cloudflared", "ngrok"):
        if shutil.which(name):
            return name
    return None


def _local_dashboard_url() -> str:
    base = os.environ.get("HERMES_DASHBOARD_URL", "http://127.0.0.1:8765").rstrip("/")
    return base if "://" in base else f"http://{base}"


class TunnelStartError(RuntimeError):
    """Tunnel binary started but never published a public URL."""


async def _spawn_tunnel(
    bin_path: str, local_url: str
) -> tuple[str, "asyncio.subprocess.Process", str]:
    """Spawn the tunnel process and wait for its public URL.

    Returns ``(provider, process, public_url)``. Raises ``TunnelStartError``
    (after killing the process) if no URL shows up within the timeout.
    """
    provider = os.path.basename(bin_path)
    if provider == "ngrok":
        cmd = [bin_path, "http", local_url, "--log=stdout"]
    else:  # cloudflared — no account, no config, random trycloudflare URL
        cmd = [bin_path, "tunnel", "--url", local_url, "--no-autoupdate"]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    stdout = proc.stdout
    assert stdout is not None  # we always pass stdout=PIPE above
    seen: list[str] = []
    deadline = time.monotonic() + 30.0
    try:
        while time.monotonic() < deadline:
            try:
                raw = await asyncio.wait_for(stdout.readline(), timeout=3.0)
            except asyncio.TimeoutError:
                continue  # still waiting for the URL, keep polling
            if not raw:
                break  # process exited before publishing a URL
            text = raw.decode(errors="replace").strip()
            seen.append(text)
            match = _TUNNEL_URL_RE.search(text)
            if match:
                return provider, proc, match.group(0)
    except Exception:
        pass
    # Failure: kill and report what the binary said.
    try:
        proc.kill()
    except Exception:
        pass
    tail = " | ".join(seen[-4:]) or "(no output)"
    raise TunnelStartError(
        f"Tunnel ({provider}) never published a public URL within 30s. Output: {tail[:300]}"
    )


class _TunnelProxy:
    """Minimal HTTP/1.1 reverse proxy — the tunnel's local entry point.

    cloudflared/ngrok forward the public HTTPS traffic here; the proxy
    rewrites the Host header back to the dashboard's loopback address so the
    core Host-header guard (DNS-rebinding defence) never sees a foreign
    hostname. Everything lives in the plugin: no core patch needed.
    """

    def __init__(self, target: str) -> None:
        self._target = target.rstrip("/")
        self._server: Optional[asyncio.AbstractServer] = None
        self._client: Optional[Any] = None
        self.port: int = 0

    async def start(self) -> int:
        import httpx

        self._client = httpx.AsyncClient(
            # No read timeout: SSE chat streams run until the turn ends.
            timeout=httpx.Timeout(connect=10.0, read=None, write=None, pool=10.0)
        )
        self._server = await asyncio.start_server(self._handle, "127.0.0.1", 0)
        assert self._server.sockets
        self.port = self._server.sockets[0].getsockname()[1]
        return self.port

    async def stop(self) -> None:
        server: Optional[asyncio.AbstractServer] = self._server
        self._server = None
        if server is not None:
            server.close()
            await server.wait_closed()
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _handle(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            await self._relay(reader, writer)
        except Exception:  # pragma: no cover — proxy must never take the plugin down
            logger.debug("proxy relay error", exc_info=True)
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def _relay(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        request_line = await reader.readline()
        if not request_line:
            return
        parts = request_line.decode("latin-1").strip().split(" ", 2)
        if len(parts) != 3:
            return
        method, raw_path, _version = parts
        headers: dict[str, str] = {}
        while True:
            line = await reader.readline()
            if line in (b"\r\n", b"\n", b""):
                break
            name, _, value = line.decode("latin-1").partition(":")
            headers[name.strip().lower()] = value.strip()
        content_length = int(headers.get("content-length", "0") or 0)
        body = await reader.readexactly(content_length) if content_length else b""

        client = self._client
        if client is None:
            return
        up_headers = {
            k: v
            for k, v in headers.items()
            if k not in ("host", "content-length", "connection", "keep-alive")
        }
        up_headers["host"] = urlparse(self._target).netloc
        up_headers["x-forwarded-host"] = headers.get("host", "")
        up_headers["x-forwarded-proto"] = "https"
        # The iOS app speaks /api/mobile/*; the dashboard serves the plugin
        # under /api/plugins/hermes-mobile/* — map so the tunnel serves the
        # app as-is (web UI paths pass through untouched).
        up_path = raw_path
        if up_path.startswith("/api/mobile/"):
            up_path = "/api/plugins/hermes-mobile/" + up_path[len("/api/mobile/") :]
        async with client.stream(method, self._target + up_path, headers=up_headers, content=body) as resp:
            status_line = f"HTTP/1.1 {resp.status_code} {resp.reason_phrase or ''}\r\n"
            writer.write(status_line.encode("latin-1"))
            for key, value in resp.headers.items():
                if key.lower() in ("transfer-encoding", "connection", "keep-alive"):
                    continue
                writer.write(f"{key}: {value}\r\n".encode("latin-1"))
            writer.write(b"\r\n")
            await writer.drain()
            async for chunk in resp.aiter_raw():
                writer.write(chunk)
                await writer.drain()


async def _cleanup_tunnel() -> None:
    global _tunnel_proc, _tunnel_url, _tunnel_provider, _tunnel_error, _tunnel_proxy
    proc, _tunnel_proc = _tunnel_proc, None
    proxy, _tunnel_proxy = _tunnel_proxy, None
    _tunnel_url = ""
    _tunnel_provider = ""
    _tunnel_error = ""
    if proxy is not None:
        await proxy.stop()
    if proc is None or proc.returncode is not None:
        return
    try:
        proc.terminate()
        await asyncio.wait_for(proc.wait(), timeout=5.0)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _atexit_kill_tunnel() -> None:
    proc = globals().get("_tunnel_proc")
    if proc is not None and getattr(proc, "returncode", 0) is None:
        try:
            proc.terminate()
        except Exception:
            pass


atexit.register(_atexit_kill_tunnel)


@router.get("/tunnel/status")
async def mobile_tunnel_status() -> dict[str, Any]:
    active = _tunnel_proc is not None and _tunnel_proc.returncode is None
    return {
        "ok": True,
        "active": active,
        "provider": _tunnel_provider if active else "",
        "publicUrl": _tunnel_url if active else "",
        "localUrl": _local_dashboard_url(),
        "error": _tunnel_error if not active else "",
    }


@router.post("/tunnel/start")
async def mobile_tunnel_start() -> dict[str, Any]:
    """Open a public HTTPS tunnel to this dashboard. Fail-closed: 400 if no
    tunnel binary is installed, 502 if the binary never published a URL.

    The tunnel points at a plugin-owned reverse proxy (``_TunnelProxy``) that
    rewrites the Host header back to loopback, so the dashboard's core
    Host-header guard never sees the public hostname — no core patch needed.
    """
    global _tunnel_proc, _tunnel_provider, _tunnel_url, _tunnel_error, _tunnel_proxy
    if _tunnel_proc is not None:
        if _tunnel_proc.returncode is None:
            return {
                "ok": True,
                "active": True,
                "provider": _tunnel_provider,
                "publicUrl": _tunnel_url,
            }
        await _cleanup_tunnel()  # stale/exited process
    bin_path = _find_tunnel_bin()
    if not bin_path:
        raise HTTPException(
            status_code=400,
            detail=(
                "No tunnel binary found. Install one: "
                "'brew install cloudflared' (recommended — quick tunnels "
                "need no account) or 'brew install ngrok'."
            ),
        )
    proxy = _TunnelProxy(_local_dashboard_url())
    try:
        proxy_port = await proxy.start()
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"Could not start local proxy: {exc}"
        ) from exc
    try:
        provider, proc, public_url = await _spawn_tunnel(
            bin_path, f"http://127.0.0.1:{proxy_port}"
        )
    except TunnelStartError as exc:
        await proxy.stop()
        _tunnel_error = str(exc)
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    _tunnel_proc = proc
    _tunnel_proxy = proxy
    _tunnel_provider = provider
    _tunnel_url = public_url
    _tunnel_error = ""
    return {
        "ok": True,
        "active": True,
        "provider": provider,
        "publicUrl": public_url,
        "proxyPort": proxy_port,
    }


@router.post("/tunnel/stop")
async def mobile_tunnel_stop() -> dict[str, Any]:
    was_active = _tunnel_proc is not None and _tunnel_proc.returncode is None
    await _cleanup_tunnel()
    return {"ok": True, "stopped": was_active}


# ---------------------------------------------------------------------------
# Cron jobs — read + control the gateway's scheduled jobs from the phone.
# Runs inside the dashboard process, so it talks to the same cron store the
# desktop ticker uses (no CLI round-trip). The bridge (dev server) does not
# ship these routes; the iOS app degrades gracefully when they 404.
# ---------------------------------------------------------------------------


def _cron_job_row(job: dict[str, Any]) -> dict[str, Any]:
    latest = job.get("latest_execution") or {}
    return {
        "id": job.get("id", ""),
        "name": job.get("name", ""),
        "prompt": job.get("prompt", ""),
        "schedule": job.get("schedule", ""),
        "scheduleDisplay": job.get("schedule_display", ""),
        "state": job.get("state", "scheduled" if job.get("enabled", True) else "paused"),
        "enabled": bool(job.get("enabled", True)),
        "nextRunAt": job.get("next_run_at"),
        "lastRunAt": job.get("last_run_at"),
        "deliver": job.get("deliver", ""),
        "skills": job.get("skills") or [],
        "latestExecution": {
            "id": latest.get("id", ""),
            "status": latest.get("status", ""),
            "startedAt": latest.get("started_at"),
            "finishedAt": latest.get("finished_at"),
        },
    }


def _load_cron_jobs() -> Any:
    try:
        from cron import jobs as cron_jobs

        return cron_jobs
    except Exception as exc:  # pragma: no cover — only when cron is unreachable
        raise HTTPException(status_code=502, detail=f"Cron store unavailable: {exc}") from exc


@router.get("/cron")
async def mobile_cron_list() -> dict[str, Any]:
    cron_jobs = _load_cron_jobs()
    try:
        rows = cron_jobs.list_jobs(include_disabled=True)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Cron store unavailable: {exc}") from exc
    return {"ok": True, "jobs": [_cron_job_row(j) for j in rows]}


@router.get("/cron/{job_id}/executions")
async def mobile_cron_executions(job_id: str) -> dict[str, Any]:
    try:
        from cron.executions import list_executions

        rows = list_executions(job_id=job_id, limit=20)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Cron store unavailable: {exc}") from exc
    if not rows:
        raise HTTPException(status_code=404, detail=f"No executions for job {job_id}")
    return {
        "ok": True,
        "executions": [
            {
                "id": e.get("id", ""),
                "status": e.get("status", ""),
                "startedAt": e.get("started_at"),
                "finishedAt": e.get("finished_at"),
                "summary": e.get("summary", ""),
            }
            for e in rows
        ],
    }


async def _cron_job_action(job_id: str, action: str) -> dict[str, Any]:
    cron_jobs = _load_cron_jobs()
    try:
        if action == "pause":
            job = cron_jobs.pause_job(job_id)
        elif action == "resume":
            job = cron_jobs.resume_job(job_id)
        elif action == "run":
            job = cron_jobs.trigger_job(job_id)
        elif action == "remove":
            removed = cron_jobs.remove_job(job_id)
            return {"ok": True, "removed": bool(removed), "id": job_id}
        else:  # pragma: no cover
            raise HTTPException(status_code=400, detail=f"Unknown action {action}")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Cron action failed: {exc}") from exc
    if job is None:
        raise HTTPException(status_code=404, detail=f"Unknown cron job {job_id}")
    return {"ok": True, "job": _cron_job_row(job)}


@router.post("/cron/{job_id}/pause")
async def mobile_cron_pause(job_id: str) -> dict[str, Any]:
    return await _cron_job_action(job_id, "pause")


@router.post("/cron/{job_id}/resume")
async def mobile_cron_resume(job_id: str) -> dict[str, Any]:
    return await _cron_job_action(job_id, "resume")


@router.post("/cron/{job_id}/run")
async def mobile_cron_run(job_id: str) -> dict[str, Any]:
    return await _cron_job_action(job_id, "run")


@router.post("/cron/{job_id}/remove")
async def mobile_cron_remove(job_id: str) -> dict[str, Any]:
    return await _cron_job_action(job_id, "remove")


# ---------------------------------------------------------------------------
# Notifications — poll endpoint for background alerts. The iOS app runs a
# Background App Refresh task that hits this and fires LOCAL notifications
# (no APNs account needed): approvals waiting for a phone verdict, plus
# cron executions that just finished.
# ---------------------------------------------------------------------------


@router.get("/notifications/pending")
async def mobile_notifications_pending() -> dict[str, Any]:
    approvals: list[dict[str, Any]] = []
    try:
        engine = _get_engine()
        for approval_id, details in engine.pending_approvals().items():
            approvals.append(
                {
                    "id": approval_id,
                    "sessionID": details.get("session_id", ""),
                    "command": details.get("command", ""),
                }
            )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Approval state unavailable: {exc}") from exc

    recent_cron: list[dict[str, Any]] = []
    try:
        from cron.executions import list_executions

        for execution in list_executions(limit=10):
            recent_cron.append(
                {
                    "jobID": execution.get("job_id", ""),
                    "status": execution.get("status", ""),
                    "claimedAt": execution.get("claimed_at"),
                    "finishedAt": execution.get("finished_at"),
                    "summary": execution.get("summary", ""),
                }
            )
    except Exception:
        pass  # cron store unreachable — approvals still matter

    return {"ok": True, "approvals": approvals, "recentCron": recent_cron}


# ---------------------------------------------------------------------------
# Skills & memory — read-only skill catalog, memory read + append. Paths come
# from HERMES_HOME (default ~/.hermes) so tests can point at a temp dir.
# ---------------------------------------------------------------------------


_SKILLS_ROOT: str | None = None
_MEMORIES_DIR: str | None = None


def _hermes_home_dir() -> Path:
    return Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))


def _skills_root_dir() -> Path:
    if _SKILLS_ROOT:
        return Path(_SKILLS_ROOT)
    return _hermes_home_dir() / "skills"


def _memories_root_dir() -> Path:
    if _MEMORIES_DIR:
        return Path(_MEMORIES_DIR)
    return _hermes_home_dir() / "memories"


def _parse_skill_md(path: Path) -> dict[str, str] | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    name = path.parent.name
    description = ""
    body = text
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) == 3:
            frontmatter = parts[1]
            body = parts[2].lstrip("\n")
            for line in frontmatter.splitlines():
                line = line.strip()
                if line.startswith("name:") and not name:
                    name = line.split(":", 1)[1].strip().strip("\"'")
                elif line.startswith("description:"):
                    description = line.split(":", 1)[1].strip().strip("\"'")
    return {"name": name, "description": description, "body": body}


def _iter_skills() -> list[dict[str, str]]:
    root = _skills_root_dir()
    if not root.is_dir():
        return []
    skills = []
    for category_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        for skill_dir in sorted(p for p in category_dir.iterdir() if p.is_dir()):
            md = skill_dir / "SKILL.md"
            if not md.is_file():
                continue
            parsed = _parse_skill_md(md)
            if parsed is not None:
                parsed["category"] = category_dir.name
                skills.append(parsed)
    return skills


def _parse_memory_file(path: Path) -> list[dict[str, Any]]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    entries = [e.strip() for e in re.split(r"\n\s*§\s*\n", text) if e.strip()]
    return [{"index": i, "content": e} for i, e in enumerate(entries)]


@router.get("/skills")
async def mobile_skills_list() -> dict[str, Any]:
    return {"ok": True, "skills": _iter_skills()}


@router.get("/skills/{skill_name}")
async def mobile_skill_detail(skill_name: str) -> dict[str, Any]:
    for skill in _iter_skills():
        if skill["name"] == skill_name:
            return {"ok": True, "skill": skill}
    raise HTTPException(status_code=404, detail=f"Unknown skill {skill_name}")


@router.get("/memory")
async def mobile_memory_get() -> dict[str, Any]:
    root = _memories_root_dir()
    return {
        "ok": True,
        "memory": _parse_memory_file(root / "MEMORY.md"),
        "user": _parse_memory_file(root / "USER.md"),
    }


class _MemoryRequest(BaseModel):
    target: str  # "memory" (agent notes) or "user" (user profile)
    content: str


@router.post("/memory")
async def mobile_memory_append(body: _MemoryRequest) -> dict[str, Any]:
    if body.target not in ("memory", "user"):
        raise HTTPException(status_code=400, detail="target must be memory|user")
    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="content is empty")
    path = _memories_root_dir() / ("MEMORY.md" if body.target == "memory" else "USER.md")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        existing = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
        with open(path, "a", encoding="utf-8") as fh:
            if existing.strip():
                fh.write("\n§\n" + content + "\n")
            else:
                fh.write(content + "\n")
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Could not write memory: {exc}") from exc
    return {"ok": True, "target": body.target, "entries": _parse_memory_file(path)}


# ---------------------------------------------------------------------------
# Cron creation + memory editing (mobile authoring surfaces)
# ---------------------------------------------------------------------------


@router.post("/cron")
async def mobile_cron_create(body: dict[str, Any]) -> dict[str, Any]:
    # Parsed as a raw dict (not a BaseModel) — pydantic 2.13's TypeAdapter
    # rejects optional-with-default fields through FastAPI's body FieldInfo
    # alias, which would 500 every create. Validation is explicit below.
    prompt = (body.get("prompt") or "").strip()
    schedule = (body.get("schedule") or "").strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="prompt is required")
    if not schedule:
        raise HTTPException(status_code=400, detail="schedule is required")
    cron_jobs = _load_cron_jobs()
    try:
        job = cron_jobs.create_job(
            prompt=prompt,
            schedule=schedule,
            name=(body.get("name") or None),
            skills=body.get("skills") or None,
            deliver=body.get("deliver") or None,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Cron create failed: {exc}") from exc
    if not body.get("enabled", True):
        try:
            cron_jobs.pause_job(job["id"])
            job = cron_jobs.get_job(job["id"]) or job
        except Exception:  # pragma: no cover — pause after create is best-effort
            pass
    return {"ok": True, "job": _cron_job_row(job)}


class _MemoryContent(BaseModel):
    content: str


def _memory_path_for(target: str) -> Path:
    if target not in ("memory", "user"):
        raise HTTPException(status_code=400, detail="target must be memory|user")
    return _memories_root_dir() / ("MEMORY.md" if target == "memory" else "USER.md")


def _memory_entries(path: Path) -> list[str]:
    if not path.exists():
        raise HTTPException(status_code=404, detail="Memory file not found")
    text = path.read_text(encoding="utf-8", errors="replace")
    return [e.strip() for e in re.split(r"\n\s*§\s*\n", text) if e.strip()]


def _write_memory_entries(path: Path, entries: list[str]) -> None:
    body = "\n\n§\n\n".join(entries)
    path.write_text(body + ("\n" if body else ""), encoding="utf-8")


@router.patch("/memory/{target}/{index}")
async def mobile_memory_update(target: str, index: int, body: _MemoryContent) -> dict[str, Any]:
    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="content is empty")
    path = _memory_path_for(target)
    try:
        entries = _memory_entries(path)
        if index < 0 or index >= len(entries):
            raise HTTPException(status_code=404, detail=f"No memory entry at index {index}")
        entries[index] = content
        _write_memory_entries(path, entries)
    except HTTPException:
        raise
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Could not update memory: {exc}") from exc
    return {"ok": True, "target": target, "entries": _parse_memory_file(path)}


@router.delete("/memory/{target}/{index}")
async def mobile_memory_delete(target: str, index: int) -> dict[str, Any]:
    path = _memory_path_for(target)
    try:
        entries = _memory_entries(path)
        if index < 0 or index >= len(entries):
            raise HTTPException(status_code=404, detail=f"No memory entry at index {index}")
        del entries[index]
        _write_memory_entries(path, entries)
    except HTTPException:
        raise
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Could not update memory: {exc}") from exc
    return {"ok": True, "target": target, "entries": _parse_memory_file(path)}

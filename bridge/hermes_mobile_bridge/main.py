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
import atexit
import json
import logging
import os
import re
import shutil
import time
import uuid
from typing import Any, Optional
from urllib.parse import urlparse

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


class MobileEffortRequest(BaseModel):
    effort: str


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
    raw_source = (row.get("source") or "unknown").lower()
    # ACP sessions (created through the mobile plugin/bridge) read as
    # "mobile" for the user — the wire source stays what the DB says.
    source = "mobile" if raw_source == "acp" else raw_source
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
        "source": source,
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
        messages.append(_mobile_msg(m))
    return {"messages": messages}


def _tool_calls_from_row(m: dict[str, Any]) -> list[dict[str, Any]]:
    calls = []
    raw_calls = m.get("tool_calls") or []
    if isinstance(raw_calls, str):
        try:
            raw_calls = json.loads(raw_calls)
        except (TypeError, json.JSONDecodeError):
            raw_calls = []
    for tc in raw_calls:
        if not isinstance(tc, dict):
            continue
        # The iOS app's HermesToolCall requires name/status/summary; status
        # enum is queued|running|succeeded|failed|waitingApproval. The
        # dashboard rows carry raw tool_calls with 'name'/'arguments' and an
        # optional 'status' (or a command string in the 'command' field).
        raw_function = tc.get("function")
        function: dict[str, Any] = raw_function if isinstance(raw_function, dict) else {}
        name = tc.get("name") or tc.get("tool_name") or function.get("name") or "tool"
        raw_status = str(tc.get("status") or "completed").lower()
        status = raw_status if raw_status in ("queued", "running", "succeeded", "failed", "waitingApproval") else "succeeded"
        arguments = tc.get("arguments") or tc.get("input") or function.get("arguments") or ""
        rendered_arguments = arguments if isinstance(arguments, str) else json.dumps(arguments, ensure_ascii=False)
        command = tc.get("command") or rendered_arguments[:300]
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


async def _resume_non_acp_session(
    session_id: str,
    text: str,
    provider: str | None = None,
    model_id: str | None = None,
) -> dict[str, Any]:
    """Continue a Desktop/Telegram session through Hermes' native resume path."""
    hermes = shutil.which("hermes")
    if not hermes:
        return {"ok": False, "error": "hermes CLI not found"}
    args = [hermes, "chat", "--quiet", "--resume", session_id, "-q", text]
    if provider and model_id:
        args.extend(["--provider", provider, "--model", model_id])
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=1800)
    except asyncio.TimeoutError:
        proc.kill()
        return {"ok": False, "error": "Hermes resume timed out"}
    return {
        "ok": proc.returncode == 0,
        "output": (stdout or b"").decode("utf-8", "replace"),
    }


@mobile_router.post("/chat")
async def mobile_chat(body: MobileChatRequest) -> StreamingResponse:
    requested_session_id = body.sessionID
    if requested_session_id:
        try:
            sessions = await _get_dashboard().list_sessions(limit=100, archived="include")
            session = next(
                (
                    row
                    for row in sessions
                    if str(row.get("id") or row.get("session_id") or "") == requested_session_id
                ),
                None,
            )
        except Exception:
            session = None
        if session is None:
            raise HTTPException(status_code=404, detail="Session not found")
        if session.get("source") != "acp":
            async def resume_existing_session():
                engine = _get_engine()
                result = await _resume_non_acp_session(
                    requested_session_id,
                    body.text,
                    engine._provider,
                    engine._model_id,
                )
                if not result.get("ok"):
                    detail = result.get("error") or result.get("output") or "Unable to resume session"
                    yield f"data: {json.dumps({'type': 'error', 'detail': str(detail)[-500:]}, ensure_ascii=False)}\n\n"
                    return
                try:
                    msgs = await _get_dashboard().get_session_messages(requested_session_id)
                except Exception:
                    msgs = []
                payload = {
                    "type": "transcript",
                    "sessionID": requested_session_id,
                    "messages": [_mobile_msg(m) for m in msgs],
                }
                yield f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                yield f"data: {json.dumps({'type': 'done'})}\n\n"

            return StreamingResponse(resume_existing_session(), media_type="text/event-stream")

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
                elif kind == "thinking":
                    yield f"data: {json.dumps({'type': 'thinking', 'text': item.get('text', '')}, ensure_ascii=False)}\n\n"
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
            # Only clear the active-turn marker when the prompt really
            # finished. If the CLIENT closed the stream mid-turn, the server
            # turn keeps running and must stay cancelable by the next /chat.
            if task is not None and engine._active_turn is task and task.done():
                engine._active_turn = None
                engine._turn_session = None

    return StreamingResponse(stream_events(), media_type="text/event-stream")


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
                "isActive": bool(r.get("is_active")),
            }
        )
    return {"models": models, "providers": sorted({m["provider"] for m in models})}


@mobile_router.post("/model")
async def mobile_model_set(body: MobileModelRequest) -> dict[str, Any]:
    provider = body.provider or body.model.partition("/")[0]
    try:
        result = await _get_dashboard().set_model(provider, body.model)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc
    engine = _get_engine()
    engine._provider = provider
    engine._model_id = body.model
    if engine._active_hermes_session:
        acp_id = engine._session_map.get(engine._active_hermes_session)
        if acp_id:
            await engine._set_session_model(acp_id, body.model)
    return {"ok": True, "provider": provider, "model": body.model, **result}


@mobile_router.get("/model/effort")
async def mobile_model_effort_get() -> dict[str, Any]:
    try:
        return await _get_dashboard().get_reasoning_effort()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc


@mobile_router.post("/model/effort")
async def mobile_model_effort_set(body: MobileEffortRequest) -> dict[str, Any]:
    try:
        return await _get_dashboard().set_reasoning_effort(body.effort)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Dashboard unreachable: {exc}") from exc


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
# Remote tunnel (Cloudflare quick tunnel / ngrok) — outbound HTTPS, no VPN.
#
# Lets the iPhone reach the bridge from outside the LAN without Tailscale or
# port-forwarding. The tunnel points at a bridge-owned reverse proxy that
# forwards back to this bridge on loopback — the bridge has no Host-header
# guard, so no header rewriting is needed here.
# ---------------------------------------------------------------------------

_TUNNEL_URL_RE = re.compile(
    r"https://[a-z0-9-]+\.(?:trycloudflare\.com|ngrok-free\.app|ngrok\.app|ngrok\.io)"
)

_tunnel_proc: Optional["asyncio.subprocess.Process"] = None
_tunnel_proxy: Optional["_TunnelProxy"] = None
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


def _local_bridge_url() -> str:
    return os.environ.get("HERMES_MOBILE_BRIDGE_URL", "http://127.0.0.1:8766").rstrip("/")


class TunnelStartError(RuntimeError):
    """Tunnel binary started but never published a public URL."""


class _TunnelProxy:
    """Minimal HTTP/1.1 reverse proxy — the tunnel's local entry point.

    cloudflared/ngrok forward the public HTTPS traffic here; the proxy
    forwards it back to this bridge on loopback. Everything lives in the
    bridge: no core patch needed.
    """

    def __init__(self, target: str) -> None:
        self._target = target.rstrip("/")
        self._server: Optional[asyncio.AbstractServer] = None
        self._client: Optional[Any] = None
        self.port: int = 0

    async def start(self) -> int:
        import httpx

        # No read timeout: SSE chat streams run until the turn ends.
        self._client = httpx.AsyncClient(
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
        except Exception:  # pragma: no cover — proxy must never take the bridge down
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
        async with client.stream(method, self._target + raw_path, headers=up_headers, content=body) as resp:
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


async def _spawn_tunnel(
    bin_path: str, local_url: str
) -> tuple[str, "asyncio.subprocess.Process", str]:
    """Spawn the tunnel process and wait for its public URL."""
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


@mobile_router.get("/tunnel/status")
async def mobile_tunnel_status() -> dict[str, Any]:
    active = _tunnel_proc is not None and _tunnel_proc.returncode is None
    return {
        "ok": True,
        "active": active,
        "provider": _tunnel_provider if active else "",
        "publicUrl": _tunnel_url if active else "",
        "localUrl": _local_bridge_url(),
        "error": _tunnel_error if not active else "",
    }


@mobile_router.post("/tunnel/start")
async def mobile_tunnel_start() -> dict[str, Any]:
    """Open a public HTTPS tunnel to this bridge. Fail-closed: 400 if no
    tunnel binary is installed, 502 if the binary never published a URL."""
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
    proxy = _TunnelProxy(_local_bridge_url())
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


@mobile_router.post("/tunnel/stop")
async def mobile_tunnel_stop() -> dict[str, Any]:
    was_active = _tunnel_proc is not None and _tunnel_proc.returncode is None
    await _cleanup_tunnel()
    return {"ok": True, "stopped": was_active}


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

"""ACP engine: spawn ``hermes-acp`` and drive chat + approvals over the
official Agent Client Protocol (the same protocol Zed/VS Code use).

No patched Hermes internals are touched — everything goes through the
published ACP server that ships with Hermes (``hermes-acp``).
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from typing import Any, Callable

logger = logging.getLogger(__name__)

try:
    from acp.client.connection import ClientSideConnection
    from acp.schema import (
        ClientCapabilities,
        Implementation,
        TextContentBlock,
    )
    from acp.transports import spawn_stdio_transport
except ImportError as exc:  # pragma: no cover
    raise RuntimeError(
        "agent-client-protocol is required: pip install agent-client-protocol"
    ) from exc


class ACPError(Exception):
    pass


class _PhoneClient:
    """Implements the ACP Client side (what the server calls on us)."""

    def __init__(self, engine: "ACPExtEngine") -> None:
        self.engine = engine

    async def session_update(self, session_id: str, update: Any, **kwargs: Any) -> None:
        await self.engine._on_session_update(session_id, update)

    async def request_permission(
        self, options: list[Any], session_id: str, tool_call: Any, **kwargs: Any
    ) -> dict[str, Any]:
        return await self.engine._on_request_permission(options, session_id, tool_call)

    def on_connect(self, conn: Any) -> None:
        # Called synchronously by the SDK (not awaited) — keep it sync.
        return None


class ACPExtEngine:
    """Owns the ``hermes-acp`` subprocess and ACP sessions.

    The iOS app maps to a Hermes session by the Hermes-side session id
    (e.g. ``20260805_...``); ACP uses its own UUID. This engine keeps the
    ``hermes_session_id -> acp_session_uuid`` mapping for active sessions.

    Chat turns subscribe to the engine's per-session delta queue; dangerous
    tool approvals are forwarded to the same queue as ``approval`` events and
    resolved through ``resolve_approval`` (called by the bridge's reply
    endpoint).
    """

    def __init__(
        self,
        *,
        acp_bin: str = "hermes-acp",
        acp_args: list[str] | None = None,
        env: dict[str, str] | None = None,
        cwd: str | None = None,
        model_id: str | None = None,
        provider: str | None = None,
    ) -> None:
        self.acp_bin = acp_bin
        self._acp_args = acp_args or []
        self._extra_env = dict(env or {})
        self._cwd = cwd or os.path.expanduser("~")
        self._model_id = model_id
        self._provider = provider

        self._transport: Any = None
        self._conn: ClientSideConnection | None = None
        self._proc: Any = None

        # hermes_session_id (dashboard id) -> acp session uuid
        self._session_map: dict[str, str] = {}
        # acp uuid -> hermes_session_id
        self._reverse_map: dict[str, str] = {}
        self._active_hermes_session: str | None = None

        # Per-acp-session queue for live chat turn events (delta/tool/approval)
        self._turn_queues: dict[str, "asyncio.Queue[dict]"] = {}
        # acp uuid -> pending permission future (verdict string)
        self._pending_permissions: dict[str, asyncio.Future] = {}
        # approval id -> acp uuid (bridge-side approval ids)
        self._approval_map: dict[str, str] = {}
        # The prompt task currently in flight (one per ACP connection).
        self._active_turn: asyncio.Task | None = None
        self._turn_session: str | None = None

    # -- lifecycle ---------------------------------------------------------

    async def start(self) -> None:
        """Spawn ``hermes-acp`` and complete the ACP handshake."""
        if self._conn is not None:
            return
        env = {k: v for k, v in os.environ.items() if k in ("HOME", "PATH", "USER", "SHELL", "TERM", "LOGNAME")}
        env.update(self._extra_env)
        # Never let configured MCP discovery block the ACP handshake.
        env.setdefault("HERMES_ACP_SKIP_CONFIGURED_MCP", "1")
        if self._provider:
            env["HERMES_PROVIDER"] = self._provider
        if self._model_id:
            env["HERMES_MODEL"] = self._model_id

        self._transport = spawn_stdio_transport(self.acp_bin, *self._acp_args, env=env, cwd=self._cwd)
        self._reader, self._writer, self._proc = await self._transport.__aenter__()

        client = _PhoneClient(self)
        self._conn = ClientSideConnection(
            client, self._writer, self._reader, use_unstable_protocol=True
        )
        await self._conn.initialize(
            protocol_version=1,
            client_capabilities=ClientCapabilities(),
            client_info=Implementation(name="hermes-mobile-bridge", version="0.1"),
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

    # -- sessions ----------------------------------------------------------

    async def new_session(self, hermes_session_id: str | None = None) -> str:
        """Create an ACP session; return the Hermes-side session id."""
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

    async def _set_session_model(self, acp_id: str, model_id: str) -> None:
        """Switch the ACP session model via the raw ``session/set_model`` RPC.

        The bundled agent-client-protocol SDK (0.9.0) does not expose
        ``set_session_model`` on ClientSideConnection, but the Hermes ACP
        server implements it; fall back to the raw wire method. Failures are
        non-fatal (the server keeps its configured default model).
        """
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
            logger.info("ACP session %s: model set to %s", acp_id, resolved)
        except Exception:
            logger.warning("set_session_model(%s) failed", model_id, exc_info=True)

    async def resume_session(self, hermes_session_id: str) -> str:
        """Resume an existing Hermes session by its Hermes-side id.

        Sessions this bridge created in this process are in ``_session_map``
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

    # -- chat --------------------------------------------------------------

    def subscribe(self, hermes_session_id: str) -> "asyncio.Queue[dict]":
        """Create/return the live queue for a chat turn on this session."""
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is None:
            raise ACPError(f"no acp session for {hermes_session_id}")
        queue: asyncio.Queue[dict] = asyncio.Queue()
        self._turn_queues[acp_id] = queue
        return queue

    def unsubscribe(self, hermes_session_id: str) -> None:
        acp_id = self._session_map.get(hermes_session_id)
        if acp_id is not None:
            self._turn_queues.pop(acp_id, None)

    async def prompt(self, hermes_session_id: str, text: str) -> dict:
        """Send a prompt and wait for the turn to complete.

        Live events (deltas, tool markers, approvals) land on the queue
        created by :meth:`subscribe`.
        """
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

    # -- permissions -------------------------------------------------------

    async def _on_request_permission(
        self, options: list[Any], session_id: str, tool_call: Any
    ) -> dict[str, Any]:
        """Called by the ACP server when a dangerous tool needs approval.

        Forwards an ``approval`` event to the live chat queue, then blocks
        until the phone's verdict arrives via :meth:`resolve_approval`.
        Fails closed to ``deny`` on timeout.
        """
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
            verdict = await asyncio.wait_for(future, timeout=60)
        except asyncio.TimeoutError:
            verdict = "deny"  # fail closed — never let a turn wedge forever
        finally:
            self._pending_permissions.pop(session_id, None)
            self._approval_map.pop(approval_id, None)

        # Mobile verdicts (once|session|always|deny) map to ACP option ids
        # (allow_once|allow_session|allow_always|deny|deny_always). The
        # installed agent-client-protocol on the server side is 0.9.x, whose
        # RequestPermissionResponse nests the outcome object:
        #   {"outcome": {"outcome": "selected", "optionId": "allow_once"}}
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
        """Resolve a pending approval by bridge-side approval id."""
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
        """Extract the human-readable security description from a ToolCallUpdate.

        The real hermes-acp adapter builds the tool call with
        ``raw_input={"command": ..., "description": ...}`` plus a tool-content
        text block ``"{description}\\n$ {command}"``.
        """
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

    # -- inbound notifications ---------------------------------------------

    async def _on_session_update(self, session_id: str, update: Any) -> None:
        """Forward ACP session updates to the chat-turn queue."""
        queue = self._turn_queues.get(session_id)
        if queue is None:
            logger.debug("session_update for %s: no queue (turn_queues=%s)", session_id, list(self._turn_queues.keys()))
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
            # The SDK stores the wire ``_meta`` under the python field
            # ``field_meta`` (alias ``_meta``).
            meta = getattr(resp, "field_meta", None) or {}
            provenance = meta.get("hermes", {}).get("sessionProvenance", {})
            return provenance.get("currentHermesSessionId")
        except Exception:
            return None


async def run_acp_probe(acp_bin: str = "hermes-acp") -> dict:
    """Lightweight probe used by ``/api/mobile/health`` and tests."""
    engine = ACPExtEngine(acp_bin=acp_bin)
    try:
        await engine.start()
        return {"ok": True, "acp": True, "pid": engine._proc.pid if engine._proc else None}
    except Exception as exc:
        return {"ok": False, "acp": True, "error": str(exc)[:200]}
    finally:
        await engine.stop()

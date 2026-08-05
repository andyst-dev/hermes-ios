"""Proxy to the official Hermes dashboard REST API.

The stock dashboard already exposes sessions, files, and the model picker;
the bridge adapts those to the compact mobile shapes the iOS app expects.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx

logger = logging.getLogger(__name__)

_DEFAULT_DASHBOARD_URL = os.environ.get("HERMES_DASHBOARD_URL", "http://127.0.0.1:8765")
_TOKEN_ENV = "HERMES_DASHBOARD_SESSION_TOKEN"


class DashboardClient:
    def __init__(
        self,
        base_url: str = _DEFAULT_DASHBOARD_URL,
        token: str | None = None,
        timeout: float = 30.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._token = token or os.environ.get(_TOKEN_ENV, "")
        self._timeout = timeout
        self._client = httpx.AsyncClient(timeout=timeout)

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self._token:
            headers["X-Hermes-Session-Token"] = self._token
        return headers

    async def close(self) -> None:
        await self._client.aclose()

    async def health(self) -> dict[str, Any]:
        try:
            resp = await self._client.get(f"{self.base_url}/api/health", headers=self._headers())
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            return {"ok": False, "error": str(exc)[:200]}

    # -- sessions ----------------------------------------------------------

    async def list_sessions(
        self,
        *,
        limit: int = 50,
        source: str | None = None,
        archived: str = "exclude",
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"limit": limit, "archived": archived}
        if source:
            params["source"] = source
        resp = await self._client.get(
            f"{self.base_url}/api/sessions", params=params, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json().get("sessions", [])

    async def get_session_messages(self, session_id: str) -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self.base_url}/api/sessions/{session_id}/messages", headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json().get("messages", [])

    async def patch_session(self, session_id: str, patch: dict[str, Any]) -> dict[str, Any]:
        resp = await self._client.patch(
            f"{self.base_url}/api/sessions/{session_id}", json=patch, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

    # -- files -------------------------------------------------------------

    async def list_files(self, path: str | None = None) -> list[dict[str, Any]]:
        params = {}
        if path:
            params["path"] = os.path.expanduser(path) if not path.startswith("/") else path
        resp = await self._client.get(
            f"{self.base_url}/api/files", params=params, headers=self._headers()
        )
        resp.raise_for_status()
        payload = resp.json()
        # Dashboard shape: {"path", "parent", "entries": [{"name", "path", "is_directory", ...}]}
        return payload.get("entries", [])

    async def read_file(self, path: str) -> dict[str, Any]:
        absolute = path if path.startswith("/") else os.path.join(os.path.expanduser("~"), path)
        resp = await self._client.get(
            f"{self.base_url}/api/files/read", params={"path": absolute}, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

    # -- models ------------------------------------------------------------

    async def model_options(self) -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self.base_url}/api/model/options", headers=self._headers()
        )
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
            f"{self.base_url}/api/model/set",
            json={"scope": "main", "provider": provider, "model": model or model_id},
            headers=self._headers(),
        )
        resp.raise_for_status()
        return resp.json()

    # -- reasoning effort --------------------------------------------------

    EFFORT_OPTIONS = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    async def get_reasoning_effort(self) -> dict[str, Any]:
        resp = await self._client.get(
            f"{self.base_url}/api/config", headers=self._headers()
        )
        resp.raise_for_status()
        agent = resp.json().get("agent") or {}
        return {
            "effort": agent.get("reasoning_effort") or "",
            "options": list(self.EFFORT_OPTIONS),
        }

    async def set_reasoning_effort(self, effort: str) -> dict[str, Any]:
        if effort not in self.EFFORT_OPTIONS:
            raise ValueError(f"invalid effort: {effort}")
        resp = await self._client.put(
            f"{self.base_url}/api/config",
            json={"config": {"agent": {"reasoning_effort": effort}}},
            headers=self._headers(),
        )
        resp.raise_for_status()
        return {"ok": True, "effort": effort}

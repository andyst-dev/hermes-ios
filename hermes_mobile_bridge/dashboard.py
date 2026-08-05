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
        params = {"path": path} if path else {}
        resp = await self._client.get(
            f"{self.base_url}/api/files", params=params, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json().get("files", [])

    async def read_file(self, path: str) -> dict[str, Any]:
        resp = await self._client.get(
            f"{self.base_url}/api/files/read", params={"path": path}, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

    # -- models ------------------------------------------------------------

    async def model_options(self) -> list[dict[str, Any]]:
        resp = await self._client.get(
            f"{self.base_url}/api/model/options", headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json().get("models", [])

    async def set_model(self, model_id: str) -> dict[str, Any]:
        resp = await self._client.post(
            f"{self.base_url}/api/model/set", json={"model": model_id}, headers=self._headers()
        )
        resp.raise_for_status()
        return resp.json()

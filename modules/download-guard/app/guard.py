#!/usr/bin/env python3
"""Poll Radarr/Sonarr queues and blocklist junk downloads (e.g. .exe bait)."""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any

LOG = logging.getLogger("download-guard")

JUNK_PATTERNS = [
    re.compile(r"Found executable", re.IGNORECASE),
    re.compile(r"\.exe\b", re.IGNORECASE),
    re.compile(r"\.bat\b", re.IGNORECASE),
    re.compile(r"\.cmd\b", re.IGNORECASE),
    re.compile(r"\.msi\b", re.IGNORECASE),
    re.compile(r"\.scr\b", re.IGNORECASE),
]

BAD_STATUSES = frozenset({"warning", "error"})
DEFAULT_COOLDOWN_SECONDS = 300


@dataclass
class Settings:
    api_key: str
    radarr_url: str
    sonarr_url: str
    interval_seconds: int = 60
    dry_run: bool = False
    cooldown_seconds: int = DEFAULT_COOLDOWN_SECONDS

    @classmethod
    def from_env(cls) -> "Settings":
        api_key = os.environ.get("API_KEY", "").strip()
        if not api_key:
            raise SystemExit("API_KEY is required")
        return cls(
            api_key=api_key,
            radarr_url=os.environ.get("RADARR_URL", "http://radarr:7878").rstrip("/"),
            sonarr_url=os.environ.get("SONARR_URL", "http://sonarr:8989").rstrip("/"),
            interval_seconds=max(5, int(os.environ.get("DOWNLOAD_GUARD_INTERVAL_SECONDS", "60"))),
            dry_run=_env_bool("DOWNLOAD_GUARD_DRY_RUN", False),
            cooldown_seconds=max(
                30, int(os.environ.get("DOWNLOAD_GUARD_COOLDOWN_SECONDS", str(DEFAULT_COOLDOWN_SECONDS)))
            ),
        )


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def collect_text(record: dict[str, Any]) -> str:
    parts: list[str] = []
    for key in ("title", "status", "trackedDownloadStatus", "trackedDownloadState"):
        value = record.get(key)
        if value:
            parts.append(str(value))
    for msg in record.get("statusMessages") or []:
        if isinstance(msg, dict):
            if msg.get("title"):
                parts.append(str(msg["title"]))
            for line in msg.get("messages") or []:
                parts.append(str(line))
        else:
            parts.append(str(msg))
    return "\n".join(parts)


def is_junk(record: dict[str, Any]) -> bool:
    status = str(record.get("trackedDownloadStatus") or "").lower()
    if status not in BAD_STATUSES:
        return False
    text = collect_text(record)
    return any(pattern.search(text) for pattern in JUNK_PATTERNS)


def build_delete_url(base_url: str, queue_id: int) -> str:
    query = urllib.parse.urlencode(
        {
            "removeFromClient": "true",
            "blocklist": "true",
            "skipRedownload": "false",
        }
    )
    return f"{base_url.rstrip('/')}/api/v3/queue/{queue_id}?{query}"


@dataclass
class ArrClient:
    name: str
    base_url: str
    api_key: str

    def _request(self, method: str, url: str) -> Any:
        req = urllib.request.Request(
            url,
            method=method,
            headers={"X-Api-Key": self.api_key, "Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
            if not body:
                return None
            return json.loads(body.decode("utf-8"))

    def fetch_queue(self) -> list[dict[str, Any]]:
        url = f"{self.base_url}/api/v3/queue?page=1&pageSize=100&includeUnknownMovieItems=true&includeUnknownSeriesItems=true"
        try:
            payload = self._request("GET", url)
        except urllib.error.HTTPError as exc:
            LOG.error("app=%s action=queue_fetch status=%s", self.name, exc.code)
            return []
        except Exception as exc:  # noqa: BLE001 — keep loop alive
            LOG.error("app=%s action=queue_fetch error=%s", self.name, exc)
            return []
        if not isinstance(payload, dict):
            return []
        records = payload.get("records") or []
        return [r for r in records if isinstance(r, dict)]

    def remediate(self, queue_id: int, dry_run: bool) -> bool:
        url = build_delete_url(self.base_url, queue_id)
        if dry_run:
            LOG.info("app=%s queue_id=%s action=dry_run_skip url=%s", self.name, queue_id, url)
            return True
        try:
            self._request("DELETE", url)
            return True
        except urllib.error.HTTPError as exc:
            LOG.error("app=%s queue_id=%s action=delete_failed status=%s", self.name, queue_id, exc.code)
            return False
        except Exception as exc:  # noqa: BLE001
            LOG.error("app=%s queue_id=%s action=delete_failed error=%s", self.name, queue_id, exc)
            return False


@dataclass
class Guard:
    settings: Settings
    clients: list[ArrClient] = field(default_factory=list)
    _last_action: dict[str, float] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.clients:
            self.clients = [
                ArrClient("radarr", self.settings.radarr_url, self.settings.api_key),
                ArrClient("sonarr", self.settings.sonarr_url, self.settings.api_key),
            ]

    def _cooldown_key(self, app: str, record: dict[str, Any]) -> str:
        download_id = record.get("downloadId") or record.get("id") or record.get("title") or "unknown"
        return f"{app}:{download_id}"

    def _in_cooldown(self, key: str, now: float) -> bool:
        last = self._last_action.get(key)
        if last is None:
            return False
        return (now - last) < self.settings.cooldown_seconds

    def process_once(self) -> int:
        remediated = 0
        now = time.time()
        for client in self.clients:
            for record in client.fetch_queue():
                if not is_junk(record):
                    continue
                queue_id = record.get("id")
                if queue_id is None:
                    continue
                key = self._cooldown_key(client.name, record)
                if self._in_cooldown(key, now):
                    LOG.debug(
                        "app=%s queue_id=%s action=cooldown_skip title=%s",
                        client.name,
                        queue_id,
                        record.get("title"),
                    )
                    continue
                title = record.get("title")
                LOG.warning(
                    "app=%s queue_id=%s title=%s status=%s action=blocklist_redownload dry_run=%s",
                    client.name,
                    queue_id,
                    title,
                    record.get("trackedDownloadStatus"),
                    self.settings.dry_run,
                )
                if client.remediate(int(queue_id), self.settings.dry_run):
                    self._last_action[key] = now
                    remediated += 1
        return remediated

    def run_forever(self) -> None:
        LOG.info(
            "starting radarr=%s sonarr=%s interval=%ss dry_run=%s",
            self.settings.radarr_url,
            self.settings.sonarr_url,
            self.settings.interval_seconds,
            self.settings.dry_run,
        )
        while True:
            try:
                self.process_once()
            except Exception as exc:  # noqa: BLE001
                LOG.exception("poll_failed error=%s", exc)
            time.sleep(self.settings.interval_seconds)


def configure_logging() -> None:
    logging.basicConfig(
        level=os.environ.get("DOWNLOAD_GUARD_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )


def main() -> None:
    configure_logging()
    settings = Settings.from_env()
    Guard(settings).run_forever()


if __name__ == "__main__":
    main()

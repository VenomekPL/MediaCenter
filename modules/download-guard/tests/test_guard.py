from __future__ import annotations

import time
from unittest.mock import MagicMock

from app.guard import ArrClient, Guard, Settings, build_delete_url, is_junk


def test_classifies_exe_caution_as_junk():
    record = {
        "id": 1,
        "title": "48AEB057.exe",
        "trackedDownloadStatus": "warning",
        "trackedDownloadState": "importPending",
        "statusMessages": [
            {
                "title": "48AEB057.exe",
                "messages": ["Caution: Found executable file with extension: '.exe'"],
            }
        ],
    }
    assert is_junk(record) is True


def test_ignores_healthy_queue_items():
    record = {
        "id": 2,
        "title": "Some.Show.S01E01.mkv",
        "trackedDownloadStatus": "ok",
        "trackedDownloadState": "downloading",
        "statusMessages": [],
    }
    assert is_junk(record) is False


def test_ignores_warning_without_junk_pattern():
    record = {
        "id": 3,
        "title": "Movie",
        "trackedDownloadStatus": "warning",
        "statusMessages": [{"messages": ["Waiting for import path"]}],
    }
    assert is_junk(record) is False


def test_build_delete_url_flags():
    url = build_delete_url("http://radarr:7878", 42)
    assert url.startswith("http://radarr:7878/api/v3/queue/42?")
    assert "removeFromClient=true" in url
    assert "blocklist=true" in url
    assert "skipRedownload=false" in url


def test_dry_run_does_not_call_delete():
    settings = Settings(
        api_key="test",
        radarr_url="http://radarr:7878",
        sonarr_url="http://sonarr:8989",
        dry_run=True,
    )
    client = ArrClient("radarr", settings.radarr_url, settings.api_key)
    client.fetch_queue = MagicMock(
        return_value=[
            {
                "id": 99,
                "downloadId": "ABC",
                "title": "bad.exe",
                "trackedDownloadStatus": "warning",
                "statusMessages": [{"messages": ["Found executable file with extension: '.exe'"]}],
            }
        ]
    )
    client.remediate = MagicMock(wraps=client.remediate)
    # Patch HTTP delete path
    client._request = MagicMock()

    guard = Guard(settings=settings, clients=[client])
    count = guard.process_once()

    assert count == 1
    client._request.assert_not_called()


def test_cooldown_prevents_double_delete():
    settings = Settings(
        api_key="test",
        radarr_url="http://radarr:7878",
        sonarr_url="http://sonarr:8989",
        dry_run=False,
        cooldown_seconds=300,
    )
    client = ArrClient("radarr", settings.radarr_url, settings.api_key)
    junk = {
        "id": 7,
        "downloadId": "SAME",
        "title": "bad.exe",
        "trackedDownloadStatus": "warning",
        "statusMessages": [{"messages": ["Found executable"]}],
    }
    client.fetch_queue = MagicMock(return_value=[junk])
    client.remediate = MagicMock(return_value=True)

    guard = Guard(settings=settings, clients=[client])
    assert guard.process_once() == 1
    assert guard.process_once() == 0
    assert client.remediate.call_count == 1

    # Expire cooldown
    guard._last_action["radarr:SAME"] = time.time() - 400
    assert guard.process_once() == 1
    assert client.remediate.call_count == 2

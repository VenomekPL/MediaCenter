#!/usr/bin/env python3
"""
Library Audit & Cleanup Tool
Scans the media library, identifies orphans, duplicates, and mismatches.
Then fixes hardlinks, removes duplicates, and triggers rescans.
"""

import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path
from collections import defaultdict
import urllib.request

# ── Configuration ──────────────────────────────────────────────
DOWNLOADS = Path(os.path.expanduser("~/Downloads"))
TV_LIBRARY = Path(os.path.expanduser("~/Videos/TvSeries"))
MOVIE_LIBRARY = Path(os.path.expanduser("~/Videos/Movies"))

SONARR_URL = "http://localhost:8022"
RADARR_URL = "http://localhost:8021"
API_KEY = "mediacenter1234567890abcdef"

MEDIA_EXTS = {".mkv", ".mp4", ".avi", ".m4v", ".wmv", ".flv", ".ts"}
SUB_EXTS = {".srt", ".sub", ".ass", ".ssa", ".idx", ".vtt"}
ALL_EXTS = MEDIA_EXTS | SUB_EXTS

DRY_RUN = "--dry-run" in sys.argv
if DRY_RUN:
    print("🔍 DRY RUN MODE - no changes will be made\n")


# ── API Helpers ────────────────────────────────────────────────
def api_get(base_url, endpoint):
    url = f"{base_url}/api/v3/{endpoint}"
    req = urllib.request.Request(url, headers={"X-Api-Key": API_KEY})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def api_post(base_url, endpoint, data=None):
    url = f"{base_url}/api/v3/{endpoint}"
    body = json.dumps(data).encode() if data else b""
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"X-Api-Key": API_KEY,
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read()) if resp.read() else {}


def api_command(base_url, name, body=None):
    """Send a command to Sonarr/Radarr."""
    payload = {"name": name}
    if body:
        payload.update(body)
    url = f"{base_url}/api/v3/command"
    req_body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=req_body, method="POST",
                                 headers={"X-Api-Key": API_KEY,
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


# ── File Helpers ───────────────────────────────────────────────
def file_size(path):
    try:
        return path.stat().st_size
    except OSError:
        return 0


def nlinks(path):
    try:
        return path.stat().st_nlink
    except OSError:
        return 0


def inode(path):
    try:
        return path.stat().st_ino
    except OSError:
        return 0


def partial_hash(path, chunk_size=65536):
    """Hash first+last 64KB for quick comparison."""
    try:
        size = path.stat().st_size
        h = hashlib.md5()
        with open(path, "rb") as f:
            h.update(f.read(chunk_size))
            if size > chunk_size * 2:
                f.seek(-chunk_size, 2)
                h.update(f.read(chunk_size))
        return h.hexdigest()
    except OSError:
        return None


def human_size(size):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"


# ── Step 1: Inventory ─────────────────────────────────────────
def scan_library():
    """Scan TV and Movie libraries, return dict of path -> stat info."""
    files = {}
    for root_dir, lib_type in [(TV_LIBRARY, "tv"), (MOVIE_LIBRARY, "movie")]:
        if not root_dir.exists():
            continue
        for f in root_dir.rglob("*"):
            if f.is_file() and f.suffix.lower() in ALL_EXTS:
                files[f] = {
                    "type": lib_type,
                    "size": file_size(f),
                    "nlinks": nlinks(f),
                    "inode": inode(f),
                }
    return files


def scan_downloads():
    """Scan downloads folder, return dict of path -> stat info."""
    files = {}
    if not DOWNLOADS.exists():
        return files
    for f in DOWNLOADS.rglob("*"):
        if f.is_file() and f.suffix.lower() in ALL_EXTS:
            files[f] = {
                "size": file_size(f),
                "nlinks": nlinks(f),
                "inode": inode(f),
            }
    return files


# ── Step 2: Find duplicates within library ─────────────────────
def find_library_duplicates(library_files):
    """Find files in the library that are duplicates of each other.
    Group by (size, partial_hash). If same content exists in library
    under different names/paths, flag it.
    """
    # Group by size first (cheap)
    by_size = defaultdict(list)
    for path, info in library_files.items():
        if info["size"] > 1_000_000 and path.suffix.lower() in MEDIA_EXTS:
            by_size[info["size"]].append(path)

    duplicates = []
    for size, paths in by_size.items():
        if len(paths) < 2:
            continue
        # Hash to confirm
        by_hash = defaultdict(list)
        for p in paths:
            h = partial_hash(p)
            if h:
                by_hash[h].append(p)
        for h, group in by_hash.items():
            if len(group) >= 2:
                # Check they're not already the same inode
                inodes = set(inode(p) for p in group)
                if len(inodes) > 1:
                    duplicates.append(group)
    return duplicates


# ── Step 3: Find files that could be re-hardlinked ────────────
def find_relinkable(library_files, download_files):
    """Find library orphans (nlinks=1) that have a matching download
    (same size + hash) and could be hardlinked."""
    orphans = {p: info for p, info in library_files.items()
               if info["nlinks"] == 1 and info["size"] > 0
               and p.suffix.lower() in MEDIA_EXTS}

    # Index downloads by size
    dl_by_size = defaultdict(list)
    for p, info in download_files.items():
        dl_by_size[info["size"]].append(p)

    relinkable = []
    for lib_path, info in orphans.items():
        candidates = dl_by_size.get(info["size"], [])
        for dl_path in candidates:
            if partial_hash(lib_path) == partial_hash(dl_path):
                relinkable.append((lib_path, dl_path))
                break
    return relinkable


# ── Step 4: DBZ Season Remapping ──────────────────────────────
DBZ_SEASON_MAP = {
    # TVDB season: (start_absolute, end_absolute, episode_count)
    1: (1, 39, 39),
    2: (40, 74, 35),
    3: (75, 107, 33),
    4: (108, 139, 32),
    5: (140, 165, 26),
    6: (166, 194, 29),
    7: (195, 219, 25),
    8: (220, 253, 34),
    9: (254, 291, 38),
}


def remap_dbz_downloads():
    """Remap DBZ download files from absolute numbering to proper seasons."""
    dbz_dl_dir = None
    for d in DOWNLOADS.iterdir():
        if d.is_dir() and "Dragon Ball Z" in d.name:
            dbz_dl_dir = d
            break
    if not dbz_dl_dir:
        print("  No DBZ downloads folder found")
        return []

    dbz_lib_dir = TV_LIBRARY / "Dragon Ball Z"
    if not dbz_lib_dir.exists():
        print("  No DBZ library folder found")
        return []

    # Scan download files, extract episode numbers
    import re
    dl_files = {}
    for f in sorted(dbz_dl_dir.iterdir()):
        if f.suffix.lower() in MEDIA_EXTS:
            m = re.search(r'S01E(\d+)', f.name)
            if m:
                ep_num = int(m.group(1))
                dl_files[ep_num] = f

    actions = []
    for season, (start, end, count) in DBZ_SEASON_MAP.items():
        season_dir = dbz_lib_dir / f"Season {season}"
        for abs_ep in range(start, end + 1):
            rel_ep = abs_ep - start + 1
            target_name = f"Dragon Ball Z - S{season:02d}E{rel_ep:02d}.mkv"
            target_path = season_dir / target_name

            if target_path.exists():
                # Already in library — check if hardlinked
                dl_file = dl_files.get(abs_ep)
                if dl_file and inode(target_path) != inode(dl_file):
                    actions.append(("relink", target_path, dl_file,
                                    f"Re-hardlink existing S{season:02d}E{rel_ep:02d}"))
                continue

            dl_file = dl_files.get(abs_ep)
            if dl_file:
                actions.append(("hardlink", target_path, dl_file,
                                f"Import S{season:02d}E{rel_ep:02d} (abs E{abs_ep:03d})"))
    return actions


# ── Step 5: Execute changes ───────────────────────────────────
def execute_hardlink(target, source, desc):
    if DRY_RUN:
        print(f"  [DRY] {desc}: {source.name} -> {target.name}")
        return True
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, target)
        print(f"  ✓ {desc}")
        return True
    except OSError as e:
        print(f"  ✗ {desc}: {e}")
        return False


def execute_relink(target, source, desc):
    if DRY_RUN:
        print(f"  [DRY] {desc}: replace {target.name} with hardlink to {source.name}")
        return True
    try:
        os.unlink(target)
        os.link(source, target)
        print(f"  ✓ {desc}")
        return True
    except OSError as e:
        print(f"  ✗ {desc}: {e}")
        return False


def execute_delete_duplicate(path, keep_path, desc):
    if DRY_RUN:
        print(f"  [DRY] DELETE {path} (keeping {keep_path.name})")
        return True
    try:
        os.unlink(path)
        print(f"  ✓ {desc}")
        return True
    except OSError as e:
        print(f"  ✗ {desc}: {e}")
        return False


# ── Main ──────────────────────────────────────────────────────
def main():
    print("=" * 70)
    print("MEDIA LIBRARY AUDIT & CLEANUP")
    print("=" * 70)

    # Scan everything
    print("\n📂 Scanning library...")
    library = scan_library()
    tv_count = sum(1 for v in library.values() if v["type"] == "tv")
    movie_count = sum(1 for v in library.values() if v["type"] == "movie")
    print(f"  TV: {tv_count} files, Movies: {movie_count} files")

    print("\n📂 Scanning downloads...")
    downloads = scan_downloads()
    print(f"  Downloads: {len(downloads)} files")

    # Orphan summary
    orphans = {p: v for p, v in library.items()
               if v["nlinks"] == 1 and p.suffix.lower() in MEDIA_EXTS}
    orphan_size = sum(v["size"] for v in orphans.values())
    print(f"\n⚠️  Orphans (nlinks=1): {len(orphans)} files ({human_size(orphan_size)})")

    # Properly hardlinked
    linked = {p: v for p, v in library.items()
              if v["nlinks"] > 1 and p.suffix.lower() in MEDIA_EXTS}
    print(f"✅ Properly hardlinked: {len(linked)} files")

    # ── Duplicates within library ──────────────────────────────
    print("\n" + "─" * 70)
    print("STEP 1: Finding library duplicates (same content, different paths)...")
    dupes = find_library_duplicates(library)
    if dupes:
        total_waste = 0
        for group in dupes:
            sizes = [file_size(p) for p in group]
            waste = sum(sizes[1:])  # Keep first, waste is the rest
            total_waste += waste
            print(f"\n  📋 DUPLICATE GROUP ({human_size(sizes[0])} each):")
            for i, p in enumerate(group):
                prefix = "  KEEP " if i == 0 else "  DEL  "
                rel = p.relative_to(p.parents[2]) if len(p.parents) > 2 else p.name
                print(f"    {prefix} {rel} (nlinks={nlinks(p)})")
        print(f"\n  Total duplicate waste: {human_size(total_waste)}")

        if not DRY_RUN:
            for group in dupes:
                keep = group[0]
                for dup in group[1:]:
                    execute_delete_duplicate(
                        dup, keep,
                        f"Remove duplicate: {dup.name}")
    else:
        print("  No exact duplicates found in library ✓")

    # ── Re-hardlink orphans to downloads ───────────────────────
    print("\n" + "─" * 70)
    print("STEP 2: Finding orphans that can be re-hardlinked to downloads...")
    relinkable = find_relinkable(library, downloads)
    if relinkable:
        relinked = 0
        for lib_path, dl_path in relinkable:
            if execute_relink(lib_path, dl_path,
                              f"Re-link {lib_path.relative_to(TV_LIBRARY if 'TvSeries' in str(lib_path) else MOVIE_LIBRARY)}"):
                relinked += 1
        print(f"\n  Re-hardlinked: {relinked}/{len(relinkable)} files")
    else:
        print("  No orphans with matching downloads found")

    # ── DBZ Season Remapping ───────────────────────────────────
    print("\n" + "─" * 70)
    print("STEP 3: Dragon Ball Z season remapping (absolute → proper seasons)...")
    dbz_actions = remap_dbz_downloads()
    if dbz_actions:
        imported = 0
        for action_type, target, source, desc in dbz_actions:
            if action_type == "hardlink":
                if execute_hardlink(target, source, desc):
                    imported += 1
            elif action_type == "relink":
                if execute_relink(target, source, desc):
                    imported += 1
        print(f"\n  DBZ: {imported} episodes processed")
    else:
        print("  No DBZ actions needed")

    # ── Check for series tracked in both Sonarr seasons ────────
    print("\n" + "─" * 70)
    print("STEP 4: Checking Sonarr/Radarr tracking...")
    try:
        sonarr_series = api_get(SONARR_URL, "series")
        print(f"  Sonarr: {len(sonarr_series)} series tracked")

        # Check for series with 0 disk files that have files on disk
        for s in sonarr_series:
            path = s.get("path", "")
            # Convert container path to host path
            host_path = path.replace("/data/Videos/TvSeries", str(TV_LIBRARY))
            p = Path(host_path)
            if p.exists():
                on_disk = sum(1 for f in p.rglob("*")
                              if f.is_file() and f.suffix.lower() in MEDIA_EXTS)
                reported = s.get("episodeFileCount", 0)
                if on_disk > 0 and reported == 0:
                    print(f"  ⚠️  {s['title']}: {on_disk} files on disk but Sonarr says 0 — needs rescan")
                elif on_disk > reported:
                    print(f"  ⚠️  {s['title']}: {on_disk} on disk vs {reported} in Sonarr — needs rescan")
    except Exception as e:
        print(f"  Sonarr API error: {e}")

    try:
        radarr_movies = api_get(RADARR_URL, "movie")
        print(f"  Radarr: {len(radarr_movies)} movies tracked")

        radarr_paths = set()
        for m in radarr_movies:
            path = m.get("path", "").replace("/data/Videos/Movies", str(MOVIE_LIBRARY))
            radarr_paths.add(Path(path).name)

        # Check for movie folders not tracked in Radarr
        untracked_movies = []
        if MOVIE_LIBRARY.exists():
            for d in sorted(MOVIE_LIBRARY.iterdir()):
                if d.is_dir() and d.name not in radarr_paths:
                    has_media = any(f.suffix.lower() in MEDIA_EXTS
                                    for f in d.iterdir() if f.is_file())
                    if has_media:
                        untracked_movies.append(d.name)
        if untracked_movies:
            print(f"\n  ⚠️  {len(untracked_movies)} movie folders NOT tracked in Radarr:")
            for m in untracked_movies:
                print(f"    - {m}")

        # Check for untracked TV series too
        sonarr_paths = set()
        for s in sonarr_series:
            path = s.get("path", "").replace("/data/Videos/TvSeries", str(TV_LIBRARY))
            sonarr_paths.add(Path(path).name)

        untracked_tv = []
        if TV_LIBRARY.exists():
            for d in sorted(TV_LIBRARY.iterdir()):
                if d.is_dir() and d.name not in sonarr_paths:
                    has_media = any(f.suffix.lower() in MEDIA_EXTS
                                    for f in d.rglob("*") if f.is_file())
                    if has_media:
                        untracked_tv.append(d.name)
        if untracked_tv:
            print(f"\n  ⚠️  {len(untracked_tv)} TV folders NOT tracked in Sonarr:")
            for t in untracked_tv:
                print(f"    - {t}")

    except Exception as e:
        print(f"  Radarr API error: {e}")

    # ── Trigger rescans ────────────────────────────────────────
    print("\n" + "─" * 70)
    print("STEP 5: Triggering library rescans...")
    if not DRY_RUN:
        try:
            api_command(SONARR_URL, "RescanSeries")
            print("  ✓ Sonarr: full library rescan triggered")
        except Exception as e:
            print(f"  ✗ Sonarr rescan failed: {e}")
        try:
            api_command(RADARR_URL, "RescanMovie")
            print("  ✓ Radarr: full library rescan triggered")
        except Exception as e:
            print(f"  ✗ Radarr rescan failed: {e}")
    else:
        print("  [DRY] Would trigger Sonarr + Radarr rescans")

    # ── Final summary ──────────────────────────────────────────
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"  Library duplicates found: {len(dupes)}")
    print(f"  Orphans re-hardlinked:    {len(relinkable)}")
    print(f"  DBZ episodes processed:   {len(dbz_actions)}")
    if DRY_RUN:
        print("\n  ⚠️  DRY RUN — no changes were made. Run without --dry-run to apply.")


if __name__ == "__main__":
    main()

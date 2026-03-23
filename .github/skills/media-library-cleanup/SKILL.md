---
name: media-library-cleanup
description: 'Clean up, audit, and fix the media library. Use when: files are misnamed, misplaced, or duplicated; orphan files detected; Sonarr/Radarr paths mismatch disk; new content is untracked; hardlinks are broken; anime episode numbering is wrong; library health check needed.'
argument-hint: 'Describe what to clean up or audit (e.g., "find duplicates", "fix misnamed movies", "full audit")'
---

# Media Library Cleanup

Audit, diagnose, and fix issues in the MediaCenter library. This includes misnamed files, broken hardlinks, path mismatches between Sonarr/Radarr and disk, duplicate content, untracked folders, and anime season remapping.

## When to Use

- User reports orphan files, duplicates, or wasted space
- Files were renamed/moved outside of Sonarr/Radarr
- Sonarr/Radarr show 0 files for a series/movie that exists on disk
- Anime episodes use absolute numbering but need TVDB season mapping
- After Transmission cleanup leaves library files with nlinks=1
- Before restarting Transmission to verify nothing will re-download
- General "is my library healthy?" checks

## Architecture

### Unified Root & Hardlinks

All containers mount the host home directory to `/data`. This enables hardlinks between Downloads and Library (same filesystem = zero extra space).

| Purpose | Host Path | Container Path |
|---------|-----------|----------------|
| Downloads | `~/Downloads` | `/data/Downloads` |
| TV Library | `~/Videos/TvSeries` | `/data/Videos/TvSeries` |
| Movie Library | `~/Videos/Movies` | `/data/Videos/Movies` |

**Key insight**: A library file with `nlinks=1` is an "orphan" — its download was cleaned. This is normal after `cleanup.sh` runs. The file is still the **only copy**. It is NOT wasted space.

### API Access

| Service | URL | API Key Source |
|---------|-----|---------------|
| Sonarr (TV) | `http://localhost:${SONARR_PORT}/api/v3/` | `.env` → `SONARR_API_KEY` or `configs/sonarr/config.xml` |
| Radarr (Movies) | `http://localhost:${RADARR_PORT}/api/v3/` | `.env` → `RADARR_API_KEY` or `configs/radarr/config.xml` |

Default ports: Sonarr=8022, Radarr=8021. Always read from `.env` or config.xml rather than hardcoding.

## Procedure

### Step 1: Assess the Situation

Before changing anything, gather facts:

1. **Scan disk** — count files, sizes, nlinks in `~/Videos/` and `~/Downloads/`
2. **Query Sonarr/Radarr** — list all tracked series/movies, compare paths to disk
3. **Identify mismatches** — files on disk not in Sonarr/Radarr, or vice versa

Use the existing audit script as a starting point:
```bash
python3 scripts/library_audit.py --dry-run
```

### Step 2: Identify Issues (by category)

Check each category in order. See [naming rules](./references/naming-rules.md) for expected formats.

#### 2a. Naming Mismatches
- **Movies**: Folder should be `Title (Year)`, file should be `Title (Year).ext`
- **TV**: Folder should be `Show Name`, episodes `Show Name - SxxExx.ext`
- **Common broken patterns**: Double parentheses `( (Year)`, URL-encoded names `In+Spectre`, unicode characters `Æon` vs ASCII `Aeon`

#### 2b. Path Mismatches (Sonarr/Radarr path ≠ disk path)
Query the API and compare:
```
GET /api/v3/series → each series has .path
GET /api/v3/movie → each movie has .path
```
Convert container paths to host paths: replace `/data/Videos/` with `~/Videos/`.

Fix via API PUT to update the path, then trigger a rescan.

#### 2c. Untracked Content
Folders on disk that don't appear in Sonarr/Radarr. These need to be added via the UI or API (lookup by title, then add with correct path).

#### 2d. Duplicates
Same content at different paths (same size + partial hash, but different inodes). Keep the one tracked by Sonarr/Radarr, delete the other.

#### 2e. Anime Episode Numbering
Anime torrents often use absolute numbering (`S01E001-S01E291`) while TVDB splits into seasons. Must create hardlinks with proper `SxxExx` naming in the correct Season folders. See the `DBZ_SEASON_MAP` pattern in `scripts/library_audit.py`.

### Step 3: Fix Issues

**Always dry-run first.** Print what would change before doing it.

| Issue | Fix |
|-------|-----|
| Wrong folder name | `mv` on disk, then update path via API PUT |
| Wrong filename | `mv` on disk, then trigger rescan |
| Path mismatch in API | API PUT to update `.path`, then rescan |
| Untracked folder | Add to Sonarr/Radarr via API or UI |
| Duplicate files | Delete the untracked copy, keep the tracked one |
| Broken hardlink (nlinks=1) | If download exists: `os.link(download, library_file)`. If not: it's fine, it's the only copy |
| Anime absolute→season | Create hardlinks: `os.link(download_S01Exxx, library_SxxExx)` |

### Step 4: Verify & Rescan

After all fixes:
1. Trigger Sonarr rescan: `POST /api/v3/command {"name": "RescanSeries"}`
2. Trigger Radarr rescan: `POST /api/v3/command {"name": "RescanMovie"}`
3. Wait 30 seconds
4. Re-query APIs to confirm file counts match disk

### Step 5: Pre-Transmission Safety Check

Before starting Transmission (especially on metered connection):
1. Check Sonarr/Radarr download queues — clear stale `downloadClientUnavailable` items
2. Check blocklists — clear if entries exist for files we've fixed
3. Verify renamed files show `hasFile=true` in the API
4. Note that RSS+automatic search is enabled — monitored missing content WILL be searched

See [diagnostic commands](./references/diagnostic-commands.md) for the specific API calls.

## Existing Tools

| Tool | Purpose |
|------|---------|
| [scripts/library_audit.py](../../../scripts/library_audit.py) | Full audit: duplicates, orphans, DBZ remapping, Sonarr/Radarr cross-check, rescans |
| [scripts/cleanup.sh](../../../scripts/cleanup.sh) | Remove finished torrents from Transmission, delete dangling downloads |
| [scripts/deduplicate.py](../../../scripts/deduplicate.py) | Find and replace duplicate files with hardlinks |
| [scripts/find_space_wasters.py](../../../scripts/find_space_wasters.py) | Find large files wasting space |

## Critical Rules

1. **Never delete the only copy** — if nlinks=1 and no download exists, that file IS the library
2. **Always dry-run first** — print actions before executing them
3. **Use hardlinks, not copies** — same filesystem means zero extra space
4. **Fix the API, not just the disk** — renaming on disk means nothing if Sonarr/Radarr still point to the old path
5. **Sonarr = TV, Radarr = Movies** — never mix them up
6. **Container paths ≠ host paths** — always convert `/data/...` to `~/...` when working on the host
7. **Trigger rescans after changes** — Sonarr/Radarr won't see changes until rescanned
8. **Check queues before starting Transmission** — stale queue items will resume downloading

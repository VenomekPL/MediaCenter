# Diagnostic Commands

Quick-reference API calls and shell commands for diagnosing library issues. All use the Sonarr/Radarr v3 API with `X-Api-Key` header.

## Disk Inventory

### Count files and sizes
```bash
# Total library stats
find ~/Videos/Movies -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | wc -l
du -sh ~/Videos/Movies ~/Videos/TvSeries ~/Downloads

# Find orphans (nlinks=1) in library
find ~/Videos -type f -links 1 \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | wc -l

# Find possible duplicates (same size)
find ~/Videos -type f -name "*.mkv" -printf '%s %p\n' | sort -n | uniq -D -w 15

# Find broken filenames (double parens, plus signs, etc.)
find ~/Videos -name "*( (*" -o -name "*+*"
```

## Sonarr (TV) API

### List all series with file counts
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8022/api/v3/series" | \
  jq '.[] | {title, path, episodeFileCount: .statistics.episodeFileCount, episodeCount: .statistics.episodeCount}'
```

### Find series with 0 files on disk
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8022/api/v3/series" | \
  jq '.[] | select(.statistics.episodeFileCount == 0 and .statistics.episodeCount > 0) | {title, path}'
```

### Check download queue
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8022/api/v3/queue?page=1&pageSize=50" | \
  jq '.records[] | {title, status, trackedDownloadStatus}'
```

### Clear a queue item (without blocklisting)
```bash
curl -s -X DELETE -H "X-Api-Key: $KEY" \
  "http://localhost:8022/api/v3/queue/ITEM_ID?removeFromClient=true&blocklist=false&skipRedownload=true"
```

### Update series path
```bash
# 1. Get the series
SERIES=$(curl -s -H "X-Api-Key: $KEY" "http://localhost:8022/api/v3/series/SERIES_ID")
# 2. Modify path in the JSON
UPDATED=$(echo "$SERIES" | jq '.path = "/data/Videos/TvSeries/New Path"')
# 3. PUT back
echo "$UPDATED" | curl -s -X PUT -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
  -d @- "http://localhost:8022/api/v3/series/SERIES_ID"
```

### Trigger rescan
```bash
curl -s -X POST -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"name": "RescanSeries"}' "http://localhost:8022/api/v3/command"
```

## Radarr (Movies) API

### List all movies with file status
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8021/api/v3/movie" | \
  jq '.[] | {title, path, hasFile, monitored}'
```

### Find monitored movies without files
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8021/api/v3/movie" | \
  jq '.[] | select(.monitored == true and .hasFile == false) | {title, path}'
```

### Check download queue
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8021/api/v3/queue?page=1&pageSize=50" | \
  jq '.records[] | {title, status, trackedDownloadStatus}'
```

### Check blocklist
```bash
curl -s -H "X-Api-Key: $KEY" "http://localhost:8022/api/v3/blocklist?page=1&pageSize=50" | jq '.totalRecords'
curl -s -H "X-Api-Key: $KEY" "http://localhost:8021/api/v3/blocklist?page=1&pageSize=50" | jq '.totalRecords'
```

### Trigger rescan
```bash
curl -s -X POST -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"name": "RescanMovie"}' "http://localhost:8021/api/v3/command"
```

## Hardlink Diagnostics

### Check if two files share an inode
```bash
stat --format='%i %n' file1.mkv file2.mkv
# Same inode number = hardlinked (same data, zero extra space)
```

### Check if library file has a download counterpart
```bash
stat --format='%h %i %n' ~/Videos/TvSeries/Show/Season\ 1/episode.mkv
# nlinks=2 means download still exists; nlinks=1 means download was cleaned
```

### Verify hardlinking works (same filesystem check)
```bash
df ~/Downloads ~/Videos
# Must be the same filesystem/device for hardlinks to work
```

## Full Audit

Run the comprehensive audit script:
```bash
# Dry run (safe, no changes)
python3 scripts/library_audit.py --dry-run

# Real run (fixes issues, triggers rescans)
python3 scripts/library_audit.py
```

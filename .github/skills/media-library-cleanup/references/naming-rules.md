# Naming Rules & Common Patterns

## Movies

### Expected Format
```
~/Videos/Movies/
  Title (Year)/
    Title (Year).ext
```

**Examples:**
```
Rock & Rule (1983)/Rock & Rule (1983).mkv
The Empty Man (2020)/The Empty Man (2020).mkv
```

### Common Broken Patterns

| Pattern | Example | Fix |
|---------|---------|-----|
| Missing year | `Rock & Rule/` | Rename to `Rock & Rule (1983)/` |
| Double parenthesis | `Rock & Rule ( (1983).mkv` | Rename to `Rock & Rule (1983).mkv` |
| No folder | `Movie.mkv` at root of Movies/ | Create `Movie (Year)/` folder, move file in |

## TV Series

### Expected Format
```
~/Videos/TvSeries/
  Show Name/
    Season 1/
      Show Name - S01E01.ext
      Show Name - S01E02.ext
    Season 2/
      Show Name - S02E01.ext
```

Season folders are optional for single-season shows but recommended.

### Common Broken Patterns

| Pattern | Example | Fix |
|---------|---------|-----|
| URL-encoded names | `In+Spectre/` | Rename to `In Spectre/` |
| Unicode characters | `Æon Flux/` | Rename to `Aeon Flux (1991)/` (match Sonarr's preference) |
| Year in TV folder | Sometimes needed for disambiguation: `Archer (2009)/` | Check what TVDB/Sonarr expects |
| Scene naming | `Show.Name.S01E01.720p.x264-GROUP.mkv` | Sonarr accepts this — no rename needed |

## Anime-Specific

### Absolute Numbering Problem
Anime torrents commonly use absolute episode numbers in a single "Season 1":
```
Dragon Ball Z S01E001.mkv  (absolute episode 1)
Dragon Ball Z S01E291.mkv  (absolute episode 291)
```

TVDB splits these into proper seasons:
```
Season 1: E001-E039 (39 eps)
Season 2: E040-E074 (35 eps)
...
Season 9: E254-E291 (38 eps)
```

### Fix: Hardlink with Proper Names
Create hardlinks (not copies) from the download file to the correct season folder:
```python
# For absolute episode 75 (= Season 3, Episode 1):
os.link(
    "~/Downloads/DBZ/Dragon Ball Z S01E075.mkv",
    "~/Videos/TvSeries/Dragon Ball Z/Season 3/Dragon Ball Z - S03E01.mkv"
)
```

The download keeps its original name. The library gets a properly-named hardlink. Same inode, zero extra space.

### When to Apply
- Check if TVDB expects multiple seasons for the show
- If Sonarr shows Season 1 complete but Seasons 2+ empty, absolute numbering is likely the issue
- Query Sonarr API for episode list to get the correct season/episode mapping

## Sonarr/Radarr Path Conventions

### Container vs Host Paths
Sonarr/Radarr run in Docker and see container paths. Host tools see host paths.

| Container Path | Host Path |
|---------------|-----------|
| `/data/Videos/TvSeries/Show Name` | `~/Videos/TvSeries/Show Name` |
| `/data/Videos/Movies/Movie (Year)` | `~/Videos/Movies/Movie (Year)` |
| `/data/Downloads/torrent-folder` | `~/Downloads/torrent-folder` |

**Always convert** when comparing API responses to disk reality.

### Path Update via API
To fix a path mismatch in Sonarr:
```
GET /api/v3/series/{id}  → get full series object
# modify .path field
PUT /api/v3/series/{id}  → send back modified object
POST /api/v3/command {"name": "RescanSeries", "seriesId": id}
```

Same pattern for Radarr with `/api/v3/movie/{id}` and `"RescanMovie"`.

## File Health Indicators

| nlinks | Meaning |
|--------|---------|
| 1 | "Orphan" — download was cleaned, this is the only copy. **Normal after cleanup.sh** |
| 2 | Healthy hardlink — one in Downloads, one in Library |
| 3+ | Multiple hardlinks — e.g., DBZ episode linked from download + multiple season folders |

**nlinks=1 does NOT mean the file is a problem.** It just means the download copy was removed. The library copy is fine.

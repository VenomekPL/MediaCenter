# Media Center for SBC (ARM/x86)

A modular, Docker-based media center solution optimized for Single Board Computers like Raspberry Pi 5 (8GB+) and x86 SBCs.

## Features
- **Native:** Kodi (with Elementum), Samba.
- **Minimal:** Radarr, Sonarr, Transmission (+ Gluetun VPN).
- **Extended:** Minimal + Audiobookshelf, Lidarr, Prowlarr, FlareSolverr, Watchtower.
- **Full:** Extended + Home Assistant, Portainer, Jellyfin.
- **Optimized Storage:** Uses "Unified Root" architecture (`/data`) to enable **Hardlinks**. Downloads are instantly imported to the library without taking up double space.
- **VPN Protected:** All torrent traffic is routed through an encrypted VPN tunnel ([Gluetun](https://github.com/qdm12/gluetun)), keeping your activity private from your ISP. Built-in **kill switch** ensures torrents stop immediately if the VPN drops — no leaks, ever.
- **Fully Configurable:** All secrets, paths, ports, and API keys are read from a single `.env` file. Clone, configure, and go.

## Prerequisites
- A Debian-based Linux distribution (Ubuntu, Raspberry Pi OS, etc.).
- `sudo` access.

## Quick Start

### 1. Clone the repository
```bash
git clone https://github.com/VenomekPL/MediaCenter.git
cd MediaCenter
```

### 2. Create your `.env` file
```bash
cp .env.example .env
nano .env
```

Fill in at minimum:
- **VPN credentials** — `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`, `WIREGUARD_PUBLIC_KEY`, `WIREGUARD_ENDPOINT_IP` (see [VPN Setup Guide](docs/vpn_setup.md))
- **Passwords** — `TRANSMISSION_PASS`, `SAMBA_PASS`
- **Network** — `LOCAL_IP` (your machine's LAN IP, e.g. `192.168.1.100`)

Optional but recommended:
- **`API_KEY`** — Shared API key for all *arr apps. Default works out of the box; for production, generate one with `openssl rand -hex 16`.
- **`TRAKT_USERNAME`** — Enables automatic watchlist sync in Radarr/Sonarr.
- **`JELLYFIN_DRM_DEVICE`** — Hardware acceleration device path (e.g. `/dev/dri/renderD128`).

All available variables are documented in `.env.example` with comments.

### 3. Start services
Choose a profile: `minimal`, `extended`, or `full`.
```bash
./start.sh full
```

On the first run, this will:
1. Check VPN credentials (warns if missing, asks to confirm).
2. Run `scripts/setup_configs.sh` — creates config directories and pre-seeds all app configs from templates using your `.env` values.
3. Run `scripts/install_native.sh` — installs Docker, Kodi, Samba, and dependencies (first run only, creates `.native_installed` marker).
4. Start all Docker containers with the chosen profile.
5. Run `scripts/link_services.sh` — connects Transmission to all *arr apps, adds indexers to Prowlarr, configures quality limits, sets up Trakt watchlists.

### 4. Verify
After startup, check that all services are healthy:
```bash
docker compose ps
```

## Web Interfaces

| Service | URL | Profile |
|---------|-----|---------|
| Transmission | `http://<ip>:8020` | minimal |
| Radarr (Movies) | `http://<ip>:8021` | minimal |
| Sonarr (TV) | `http://<ip>:8022` | minimal |
| Lidarr (Music) | `http://<ip>:8023` | extended |
| Prowlarr (Indexers) | `http://<ip>:8024` | extended |
| Audiobookshelf | `http://<ip>:8025` | extended |
| Jellyfin | `http://<ip>:8026` | full |
| Home Assistant | `http://<ip>:8027` | full |
| Portainer | `https://<ip>:9443` | full |

All ports are configurable via `.env`.

## Post-Installation

- **Kodi:** Open Kodi and install the Elementum plugin from `~/Downloads/repository.elementum.zip`.
- **Samba:** Shares for `Videos`, `Music`, `Books`, and `Audiobooks` are configured automatically. Connect using your system username and the `SAMBA_PASS` from `.env`.
- **Trakt:** If `TRAKT_USERNAME` is set in `.env`, watchlists are synced to Radarr/Sonarr automatically. Open Radarr/Sonarr → Settings → Import Lists → Trakt Watchlist and click "Authenticate with Trakt" to authorize.

For detailed configuration (quality profiles, Trakt integration, download logic), see the [Configuration Guide](docs/configuration_guide.md).

## Maintenance

**Stop all services:**
```bash
./stop.sh
```

**Update containers:**
```bash
./update.sh full
```

**Cleanup finished torrents & dangling downloads:**
```bash
./scripts/cleanup.sh
```

**Library audit** (find duplicates, fix hardlinks, check Sonarr/Radarr tracking):
```bash
python3 scripts/library_audit.py --dry-run   # preview changes
python3 scripts/library_audit.py              # apply fixes + trigger rescans
```

**Find space wasters:**
```bash
python3 scripts/find_space_wasters.py
```

## Architecture

```
~/                          ← DATA_ROOT_PATH (mounted as /data in containers)
├── Downloads/              ← Transmission downloads here
│   └── Movie.Name.2024/   ← Torrent folder
│       └── movie.mkv
└── Videos/
    ├── Movies/             ← Radarr library (hardlinked from Downloads)
    │   └── Movie Name (2024)/
    │       └── Movie Name (2024).mkv  ← Same inode as Downloads copy
    └── TvSeries/           ← Sonarr library (hardlinked from Downloads)
        └── Show Name/
            └── Season 1/
                └── Show Name - S01E01.mkv
```

**Hardlinks** mean the movie file in `Videos/` and the one in `Downloads/` are the **same file on disk** — zero extra space. When `cleanup.sh` removes finished torrents, the library copy remains.

**VPN routing:** Transmission runs inside Gluetun's network (`network_mode: service:gluetun`). All *arr apps connect to Transmission at `gluetun:9091` (not `transmission:9091`). The kill switch blocks all traffic if the VPN tunnel drops.

## Project Structure
```
├── .env.example            ← Template — copy to .env and fill in
├── docker-compose.yml      ← Includes all modules
├── start.sh / stop.sh / update.sh  ← Lifecycle scripts
├── modules/                ← One compose.yaml per service
│   ├── gluetun/            ← VPN tunnel (WireGuard/OpenVPN)
│   ├── transmission/       ← Torrent client (routes through gluetun)
│   ├── radarr/             ← Movie management
│   ├── sonarr/             ← TV series management
│   ├── lidarr/             ← Music management
│   ├── prowlarr/           ← Indexer manager
│   ├── flaresolverr/       ← Cloudflare CAPTCHA solver
│   ├── jellyfin/           ← Media streaming server
│   ├── audiobookshelf/     ← Audiobook/podcast server
│   ├── home-assistant/     ← Home automation
│   ├── portainer/          ← Docker management UI
│   └── watchtower/         ← Auto-update containers
├── configs/                ← Template configs (pre-seeded on first run)
├── config/                 ← Live container configs (gitignored)
├── scripts/                ← Helper scripts
│   ├── setup_configs.sh    ← Pre-seeds configs from .env
│   ├── link_services.sh    ← Auto-connects all services via API
│   ├── install_native.sh   ← Installs Docker, Kodi, Samba
│   ├── cleanup.sh          ← Removes finished torrents
│   ├── library_audit.py    ← Library health: dupes, orphans, tracking
│   ├── deduplicate.py      ← Hardlink deduplication
│   └── find_space_wasters.py ← Space usage analysis
├── docs/                   ← Guides and documentation
└── .github/skills/         ← AI agent skills for library cleanup
```

## Documentation
- [Configuration Guide](docs/configuration_guide.md) — Detailed setup and automation.
- [VPN Setup Guide](docs/vpn_setup.md) — VPN tunnel and kill switch.
- [Copilot Context](docs/copilot.md) — Project rules and architectural decisions.
- `config/`: (Created on run) Persistent configuration data for containers.

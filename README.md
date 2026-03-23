# Media Center for SBC (ARM/x86)

A modular, Docker-based media center solution optimized for Single Board Computers like Raspberry Pi 5 (8GB+) and x86 SBCs.

## Features
- **Native:** Kodi (with Elementum), Samba.
- **Minimal:** Radarr, Sonarr, Transmission.
- **Extended:** Minimal + Audiobookshelf, Lidarr, Prowlarr, FlareSolverr, Watchtower.
- **Full:** Extended + Home Assistant, Portainer, Jellyfin.
- **Optimized Storage:** Uses "Unified Root" architecture (`/data`) to enable **Hardlinks**. Downloads are instantly imported to the library without taking up double space.
- **VPN Protected:** All torrent traffic is routed through an encrypted VPN tunnel ([Gluetun](https://github.com/qdm12/gluetun)), keeping your activity private from your ISP. Built-in **kill switch** ensures torrents stop immediately if the VPN drops — no leaks, ever.

## Prerequisites
- A Debian-based Linux distribution (Ubuntu, Raspberry Pi OS, etc.).
- `sudo` access.

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/VenomekPL/MediaCenter.git
   cd MediaCenter
   ```

2. **Run the installer and start services:**
   Choose a profile: `minimal`, `extended`, or `full`.
   ```bash
   ./start.sh full
   ```
   *Note: The first run will install Docker, Kodi, and Samba natively on your system. It will also auto-discover your hardware and configure `.env` for you.*

3. **Configure VPN (Required):**
   Edit the `.env` file and fill in your VPN provider credentials. All torrent traffic is routed through this tunnel.
   ```bash
   nano .env
   ```
   We recommend using WireGuard with **Mullvad** (€5/mo, no-logs, no email needed).
   See the [VPN Setup Guide](docs/vpn_setup.md) for detailed instructions. At minimum, set:
   - `VPN_SERVICE_PROVIDER` — `custom` (recommended) or a provider name
   - `VPN_TYPE` — `wireguard` (recommended) or `openvpn`
   - `WIREGUARD_PRIVATE_KEY` / `WIREGUARD_ADDRESSES` (from your downloaded `.conf`)
   - `WIREGUARD_PUBLIC_KEY` / `WIREGUARD_ENDPOINT_IP` / `WIREGUARD_ENDPOINT_PORT` (for custom provider)

## Post-Installation
For detailed configuration steps, including **Trakt integration** and **Quality Profiles**, please read the [Configuration Guide](docs/configuration_guide.md).

- **Configuration Script:**
  We provide a helper script to automatically link services (Radarr/Sonarr <-> Transmission/Prowlarr) and apply recommended settings.
  ```bash
  ./scripts/link_services.sh
  ```
  *Run this script after all services are up and running.*

- **Kodi:** Open Kodi and install the Elementum plugin from `~/Downloads/repository.elementum.zip`.
- **Samba:** Shares are automatically configured for `Videos`, `Music`, `Books`, and `Audiobooks`. Use your system username and the password set in `.env` (`SAMBA_PASS`).
- **Web Interfaces:**
  - Transmission: `http://<ip>:8020`
  - Radarr: `http://<ip>:8021`
  - Sonarr: `http://<ip>:8022`
  - Lidarr: `http://<ip>:8023`
  - Prowlarr: `http://<ip>:8024`
  - Audiobookshelf: `http://<ip>:8025`
  - Jellyfin: `http://<ip>:8026`
  - Home Assistant: `http://<ip>:8027`
  - Portainer: `https://<ip>:9443`

## Maintenance

- **Stop services:**
  ```bash
  ./stop.sh full
  ```

- **Update services:**
  ```bash
  ./update.sh full
  ```

- **Cleanup:**
  Remove finished torrents from Transmission:
  ```bash
  ./scripts/cleanup.sh
  ```

- **Deduplication:**
  Fix broken hardlinks and reclaim space:
  ```bash
  ./scripts/deduplicate.py
  ```
  *See [Duplicate Removal Guide](docs/duplicate_removal.md) for details.*

## Documentation
- [Configuration Guide](docs/configuration_guide.md): Detailed setup instructions.
- [VPN Setup Guide](docs/vpn_setup.md): How the VPN tunnel and kill switch work.
- [Duplicate Removal](docs/duplicate_removal.md): How to fix hardlinks and save space.
- [Copilot Context](docs/copilot.md): Project rules and architectural decisions.

## Project Structure
- `modules/`: Individual Docker Compose configurations for each service.
- `scripts/`: Helper scripts for installation, configuration, and maintenance.
- `config/`: (Created on run) Persistent configuration data for containers.

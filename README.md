# Media Center for SBC (ARM/x86)

A modular, Docker-based media center solution optimized for Single Board Computers like Raspberry Pi 5 (8GB+) and x86 SBCs.

## Features
- **Native:** Kodi (with Elementum), Samba.
- **Minimal:** Radarr, Sonarr, Transmission.
- **Extended:** Minimal + Audiobookshelf, Lidarr, Prowlarr, FlareSolverr, Watchtower.
- **Full:** Extended + Home Assistant, Portainer, Jellyfin.
- **Optimized Storage:** Uses "Unified Root" architecture (`/data`) to enable **Hardlinks**. Downloads are instantly imported to the library without taking up double space.

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

3. **Configure (Optional):**
   If you want to change default passwords or paths, edit the `.env` file created after the first run.
   ```bash
   nano .env
   ```

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

## Project Structure
- `modules/`: Individual Docker Compose configurations for each service.
- `scripts/`: Helper scripts for installation, configuration, and maintenance.
- `config/`: (Created on run) Persistent configuration data for containers.

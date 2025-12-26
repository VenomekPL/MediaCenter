# Media Center for SBC (ARM/x86)

A modular, Docker-based media center solution optimized for Single Board Computers like Raspberry Pi 5 (8GB+) and x86 SBCs.

## Features
- **Native:** Kodi (with Elementum), Samba.
- **Minimal:** Radarr, Sonarr, Transmission.
- **Extended:** Minimal + Audiobookshelf, Lidarr, Prowlarr, Watchtower.
- **Full:** Extended + Home Assistant, Portainer, Jellyfin, Nginx Proxy Manager.

## Prerequisites
- A Debian-based Linux distribution (Ubuntu, Raspberry Pi OS, etc.).
- Docker and Docker Compose v2 installed.
- `jq` and `curl` installed (`sudo apt install jq curl`).

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/VenomekPL/MediaCenter.git
   cd MediaCenter
   ```

2. **Configure (Optional):**
   Copy `.env.example` to `.env` and adjust paths or passwords if needed. The `start.sh` script will attempt to auto-discover hardware and create this for you if it doesn't exist.
   ```bash
   cp .env.example .env
   nano .env
   ```

3. **Run the installer and start services:**
   Choose a profile: `minimal`, `extended`, or `full`.
   ```bash
   sudo ./start.sh full
   ```
   *Note: The first run will install Kodi and Samba natively on your system.*

## Post-Installation
- **Kodi:** Open Kodi and install the Elementum plugin from `~/Downloads/repository.elementum.zip`.
- **Samba:** Configure your shares in `/etc/samba/smb.conf`.
- **Web Interfaces:**
  - Transmission: `http://<ip>:8020`
  - Radarr: `http://<ip>:8021`
  - Sonarr: `http://<ip>:8022`
  - Lidarr: `http://<ip>:8023`
  - Prowlarr: `http://<ip>:8024`
  - Audiobookshelf: `http://<ip>:8025`
  - Jellyfin: `http://<ip>:8026`
  - Home Assistant: `http://<ip>:8027`
  - Nginx Proxy Manager: `http://<ip>:8028`
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

## Project Structure
- `modules/`: Individual Docker Compose configurations for each service.
- `scripts/`: Helper scripts for hardware discovery and native installation.
- `config/`: (Created on run) Persistent configuration data for containers.

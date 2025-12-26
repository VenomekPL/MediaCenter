# Copilot Memory & Alignment

This document serves as a persistent memory for GitHub Copilot to track project rules, goals, workflows, decisions, and roadblocks.

## Project Overview
- **Goal:** Complete media center solution for ARM/x86 SBC on Linux.
- **Technology Stack:** Linux, Docker Compose (v2), ARM/x86 architecture.
- **Repository:** https://github.com/VenomekPL/MediaCenter.git
- **Target Hardware:** Raspberry Pi 5 8GB+ or equivalent (optimizing for 8GB-16GB, but functional on 4GB).

## Installation Levels (Docker Profiles)
1. **Minimal:** Radarr, Sonarr, Transmission.
2. **Extended:** Minimal + Audiobookshelf, Lidarr, Prowlarr, Watchtower.
3. **Full:** Extended + Home Assistant, Portainer, Jellyfin, Nginx Proxy Manager.

## Non-Containerized Components (Native)
- **Kodi:** Media player (direct hardware access).
  - **Plugins:** Elementum, Elementum Burst, Elementum Context Menu.
- **Samba:** File sharing.

## Rules & Workflows
- **Git Workflow:** Use `adam.grodzki@3studio.online` / `AngeIV` for commits.
- **Exclusions:** Build data for Python, C++, and Shell scripts are ignored via `.gitignore`.
- **Modular Structure:** Each service in `modules/<service_name>/` with its own configuration.
- **Configuration:** Use `.env` for all passwords, paths, and environment-specific variables.
- **Scripts:** `start.sh`, `stop.sh`, `update.sh` in the root directory. Other scripts in `scripts/`.
- **Automation:** `start.sh` handles hardware discovery, pre-seeding configurations, and native installation.
- **Pre-seeding:** Default configurations for Transmission and *arr apps are stored in `configs/` and processed by `scripts/setup_configs.sh`.
- **Service Linking:** (Planned) `scripts/link_services.sh` will use APIs to link Transmission and *arr apps automatically.
- **Documentation:** Keep `README.md` updated with any changes to profiles, services, or installation steps.

## Important Decisions
- **Docker Compose v2:** Utilizing profiles for installation levels.
- **Native Kodi/Samba:** Decided for better hardware integration and performance on SBCs.
- **Elementum over Jackett:** Using Kodi-native Elementum for torrent streaming.
- **Containerized Nginx Proxy Manager:** Chosen for ease of use (GUI) and SSL management.
- **Watchtower:** Included in Extended/Full for automated container updates.
- **Hardlinks:** Enabled in Radarr/Sonarr/Lidarr. This allows seeding from `Downloads` while having organized, renamed files in `Videos` for Samba/Kodi.
- **Samba Strategy:** Share only the organized `Videos`, `Music`, and `Books` folders. The `Downloads` folder remains hidden from the non-technical user to avoid confusion.
- **Cleanup:** `scripts/cleanup.sh` is called by `update.sh`. It removes finished torrents via Transmission API and deletes "dangling" files (link count = 1) in `Downloads` that aren't in the library.
- **Standardized Ports:** All web interfaces mapped to the 8020-8028 range for consistency, while keeping Portainer on 9443.

## Technologies Used
- Docker & Docker Compose v2
- Linux (ARM/x86)
- Kodi & Samba (Native)
- *arr Suite (Radarr, Sonarr, Lidarr, Prowlarr)
- Transmission, Jellyfin, Home Assistant, Portainer, Audiobookshelf
- Elementum (Kodi Plugin)
- Nginx Proxy Manager (NPM)
- Watchtower

## Roadblocks & Solutions
- *To be populated as encountered.*

## To-Do List
- [x] Implement hardware discovery script (`scripts/discover_hardware.sh`).
- [x] Automate `start.sh` to run discovery and native installation.
- [ ] Configure Elementum in Kodi (via `scripts/install_native.sh`).
- [ ] Refine Samba configuration for media sharing.
- [x] Implement Nginx Proxy Manager module.
- [x] Implement Watchtower module.

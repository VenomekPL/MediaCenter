# Media Center Configuration Guide

This guide explains the components of your Media Center, how to configure them, and how to achieve your specific automation goals.

## 1. Component Overview

### **Watchtower**
*   **What it is:** An automated updater for your Docker containers.
*   **How to use it:** It runs in the background. Once a day, it checks if newer versions of your apps (Radarr, Sonarr, etc.) are available. If yes, it downloads them and restarts the container automatically. You don't need to do anything.

### **Audiobookshelf**
*   **What it is:** Like Plex/Jellyfin, but specifically for Audiobooks and Podcasts.
*   **How to use it:**
    1.  Go to `http://<ip>:8025`.
    2.  Point it to your `/data/audiobooks` folder (mapped from `~/Documents/audiobooks`).
    3.  It will scan your files and provide a nice player interface for phone/browser, remembering your progress.

---

## 2. Trakt Integration

### **Kodi (Trakt Plugin)**
To sync your watched status and rate movies/episodes from Kodi:
1.  Open Kodi.
2.  Go to **Add-ons** -> **Search**.
3.  Search for **"Trakt"**.
4.  Install the official **Trakt.tv** script.
5.  Open the addon settings and authorize it with your Trakt account (it will give you a code to enter on `trakt.tv/activate`).
6.  **Context Menu:** The addon automatically adds "Rate on Trakt" and "Toggle Watched" to your context menu.

### **Radarr & Sonarr (Watchlist Sync)**
We have automated the setup of Trakt Watchlists via the `link_services.sh` script.
*   **Radarr:** Syncs your Trakt Watchlist (Movies) with "Search on Add" enabled.
*   **Sonarr:** Syncs your Trakt Watchlist (Shows) with "Monitor First Season" and "Search for Missing Episodes" enabled.

**To verify or change settings:**
1.  Open Radarr (`:8021`) or Sonarr (`:8022`).
2.  Go to **Settings** -> **Import Lists**.
3.  Edit the **Trakt Watchlist** entry.
4.  You must click **Authenticate with Trakt** manually if the list is disabled (the script sets it up but cannot log you in).

---

## 3. Automation & Download Logic

### **"Download First Episode Only" Logic**
Sonarr is designed to monitor entire seasons or series. To achieve your specific "Download 1, Watch 1, Delete 1, Download Next" flow, you need a specific setup:

1.  **In Sonarr:**
    *   When adding a show, set **Monitor** to **"None"**.
    *   Go to the show page, click the "Bookmark" flag next to **Season 1, Episode 1** to monitor *only* that episode.
    *   Sonarr will download it.
2.  **Automation (The "Next Up" Flow):**
    *   This requires a custom script or a tool like **"Upcyclarr"** or a webhook.
    *   *Native Solution:* There is no single checkbox for "Maintain 1 Unwatched".
    *   *Workaround:* Use the **Trakt** integration in Kodi. When you finish an episode, Trakt marks it watched. Sonarr sees this (if "Import List Sync" is on). You can configure Sonarr to **Unmonitor Deleted Episodes**.
    *   *Manual but Easy:* Use the "Search" button in Sonarr (Interactive Search) or just click the monitor flag for the next episode when you are ready.

### **Quality Profiles**
We have pre-configured basic profiles via script:
*   **Radarr:** Max ~66MB/min (~4GB/hour).
*   **Sonarr:** Max ~25MB/min (~1.5GB/hour).

**To adjust manually:**
1.  Go to **Settings** -> **Quality**.
2.  Edit the **HD - 1080p** or create a new **4K** profile.
3.  On the right side, adjust the **Quality Size** sliders.

---

## 4. Trackers (Prowlarr)

We have automated the addition of these trackers:
*   **The Pirate Bay** (General)
*   **Nyaa** (Anime)
*   **1337x** (General)

**FlareSolverr Integration:**
We have included **FlareSolverr** in the stack. This service automatically solves Cloudflare CAPTCHAs, which is required for sites like **1337x** and sometimes **The Pirate Bay**. Prowlarr is pre-configured to use FlareSolverr as a proxy for these indexers.

**To add more:**
1.  Go to Prowlarr (`:8024`).
2.  Click **Indexers** -> **Add Indexer**.
3.  Search for the tracker name.
4.  **Excluding Russian Trackers:** Simply do not add trackers like *Rutracker* or *Rutor*. Prowlarr only uses what you add.

---

## 5. Seeding & File Management

*   **Hardlinks:** Your setup uses Hardlinks. This means the file in `/downloads` and the file in `/movies` point to the *same data on disk*. It takes up space only once.
*   **Seeding:** You can delete the file from `/movies` (via Kodi/Samba) and the seed will continue in `/downloads`. Or vice versa.
*   **Ratio Limit:** We have configured Transmission to stop seeding automatically when a ratio of **2.0** is reached.


# Managing Disk Space and Hardlinks

The Media Center stack is designed to use **hardlinks**. This means that when a file is downloaded by Transmission and imported by Sonarr/Radarr, it doesn't take up twice the space on your disk. Instead, both the "seed" file in downloads and the "library" file point to the same physical data on the drive.

However, sometimes things go wrong (e.g., manual moves, file system issues), and you end up with actual duplicate copies instead of hardlinks.

## The Deduplication Script

We provide a tool to scan your media library, identify duplicate files that *should* be hardlinks (identical content, but different inodes), and fix them automatically.

### Location
`scripts/deduplicate.py`

### Usage

1. **Dry Run (Safe Mode)**
   This will list potential duplicates without making any changes. It asks for confirmation for each file.
   ```bash
   ./scripts/deduplicate.py
   ```

2. **Automatic Mode**
   This will automatically replace duplicates with hardlinks without asking for confirmation.
   **Warning:** Only run this if you are sure.
   ```bash
   ./scripts/deduplicate.py --auto
   ```

### How it works
1. The script recursively scans the current directory (or the directory you run it from).
2. It groups files by size.
3. For files of the same size, it calculates a checksum (SHA256) of the first 4KB (and potentially the full file if unsure) to confirm they are identical.
4. It checks the "Inode" number. If the inodes are different, it means they are separate copies taking up extra space.
5. It deletes one copy and recreates it as a hardlink to the other, freeing up the space immediately.

### Why is this important?
- **Space:** Recover significant disk space (often 50% of your usage if hardlinks failed completely).
- **Seeding:** Allows you to continue seeding torrents while having organized files in your library.

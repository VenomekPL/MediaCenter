import os
import collections

# Paths
DOWNLOADS = "/home/angeiv/Downloads"
MOVIES = "/home/angeiv/Videos/Movies"
TV = "/home/angeiv/Videos/TvSeries"

# Extensions to check
EXTS = ('.mkv', '.mp4', '.avi')

def get_files(base_path):
    file_map = [] # List of (size, filename, inode, fullpath)
    for root, _, files in os.walk(base_path):
        for f in files:
            if f.lower().endswith(EXTS):
                path = os.path.join(root, f)
                try:
                    stat = os.stat(path)
                    file_map.append({
                        'size': stat.st_size,
                        'name': f,
                        'inode': stat.st_ino,
                        'path': path
                    })
                except OSError:
                    pass
    return file_map

print("Scanning file systems...")
downloads_files = get_files(DOWNLOADS)
library_files = get_files(MOVIES) + get_files(TV)

# Index library by size
library_by_size = collections.defaultdict(list)
for f in library_files:
    library_by_size[f['size']].append(f)

duplicates = []

for d_file in downloads_files:
    size = d_file['size']
    if size in library_by_size:
        for l_file in library_by_size[size]:
            # If inodes are different, it is a copy (wasted space)
            if d_file['inode'] != l_file['inode']:
                duplicates.append((d_file, l_file))

print(f"Found {len(duplicates)} pairs of duplicate files (wasted space).")
for d, l in duplicates:
    print(f"DUPLICATE: {d['name']}")
    print(f"  Download: {d['path']}")
    print(f"  Library:  {l['path']}")
    print(f"  Size:     {d['size'] / 1024 / 1024:.2f} MB")
    print("-" * 20)

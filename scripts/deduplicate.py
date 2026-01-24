#!/usr/bin/env python3
import os
import collections
import hashlib
import sys

# Color codes
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
RESET = '\033[0m'

# Paths
DOWNLOADS = "/home/angeiv/Downloads"
MOVIES = "/home/angeiv/Videos/Movies"
TV = "/home/angeiv/Videos/TvSeries"

# Extensions to check
EXTS = ('.mkv', '.mp4', '.avi')

def get_files(base_path):
    file_map = [] # List of (size, filename, inode, fullpath)
    if not os.path.exists(base_path):
        return []
        
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

def are_files_identical(path1, path2):
    """Compares files by reading chunks from start, middle, and end."""
    try:
        size = os.path.getsize(path1)
        if size != os.path.getsize(path2):
            return False
        
        # Check start, middle, end 4KB
        with open(path1, 'rb') as f1, open(path2, 'rb') as f2:
            # Start
            if f1.read(4096) != f2.read(4096): return False
            
            # Middle
            if size > 8192:
                f1.seek(size // 2)
                f2.seek(size // 2)
                if f1.read(4096) != f2.read(4096): return False
                
            # End
            if size > 4096:
                f1.seek(-4096, 2)
                f2.seek(-4096, 2)
                if f1.read(4096) != f2.read(4096): return False
                
        return True
    except Exception as e:
        print(f"{RED}Error comparing files: {e}{RESET}")
        return False

def main():
    auto_mode = "--auto" in sys.argv
    
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
                # If inodes are different, potential duplicate
                if d_file['inode'] != l_file['inode']:
                    if are_files_identical(d_file['path'], l_file['path']):
                        duplicates.append((d_file, l_file))

    if not duplicates:
        print(f"{GREEN}No space-wasting duplicates found!{RESET}")
        return

    print(f"Found {YELLOW}{len(duplicates)}{RESET} pairs of duplicate files.")
    
    saved_space = 0
    
    for i, (d, l) in enumerate(duplicates, 1):
        mb_size = d['size'] / 1024 / 1024
        print(f"\n[{i}/{len(duplicates)}] Size: {mb_size:.2f} MB")
        print(f"  Download: {d['path']}")
        print(f"  Library:  {l['path']}")
        
        do_fix = False
        if auto_mode:
            do_fix = True
        else:
            response = input(f"{YELLOW}Replace Download file with hardlink to Library file? [y/n/all]: {RESET}").lower()
            if response == 'all':
                auto_mode = True
                do_fix = True
            elif response == 'y':
                do_fix = True
        
        if do_fix:
            try:
                # Create temp hardlink to ensure atomic operation or safe replacement
                # Using ln -f equivalent: os.unlink dest then os.link src dest
                if os.path.exists(d['path']):
                    os.unlink(d['path'])
                os.link(l['path'], d['path'])
                print(f"{GREEN}Fixed! Hardlink created.{RESET}")
                saved_space += d['size']
            except OSError as e:
                print(f"{RED}Failed to link: {e}{RESET}")
        else:
            print("Skipped.")

    if saved_space > 0:
        print(f"\n{GREEN}Total space reclaimed: {saved_space / 1024 / 1024:.2f} MB{RESET}")

if __name__ == "__main__":
    main()

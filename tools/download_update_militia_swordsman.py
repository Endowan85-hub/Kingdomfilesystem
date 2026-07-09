"""
Download latest Militia Swordsman ZIP from PixelLab and re-organize sprites.
Outputs diagonal directions only (se, sw, ne, nw).
Run from any directory.
"""

import os, shutil, zipfile, urllib.request

API_KEY      = "5ecba419-72b5-49b9-891f-ea46597c3065"
CHARACTER_ID = "40b2ad26-1bc8-4268-9a4a-c76c975ba7d7"
UNIT_KEY     = "militia_swordsman"
ATTACK_ANIM  = "sword_slash"

BASE_DIR  = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units"
TOOLS_DIR = r"C:\Users\Patrick\dev\kingdom-(test)\tools"

# Only diagonals — cardinals not needed by the game
DIAG_DIRS = {
    "south-east": "se",
    "south-west": "sw",
    "north-east": "ne",
    "north-west": "nw",
}

unit_dir = os.path.join(BASE_DIR, UNIT_KEY)
raw_dir  = os.path.join(unit_dir, "raw")
out_dir  = os.path.join(unit_dir, "sprites")
zip_path = os.path.join(TOOLS_DIR, f"{UNIT_KEY}.zip")


def download():
    print("Downloading fresh ZIP from PixelLab...")
    url = f"https://api.pixellab.ai/mcp/characters/{CHARACTER_ID}/download"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req) as resp, open(zip_path, "wb") as f:
        f.write(resp.read())
    print(f"  Downloaded: {os.path.getsize(zip_path) // 1024} KB")


def extract():
    print("Extracting...")
    if os.path.isdir(raw_dir):
        shutil.rmtree(raw_dir)
    os.makedirs(raw_dir)
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(raw_dir)
    # Find the extracted subfolder
    items = [d for d in os.listdir(raw_dir) if os.path.isdir(os.path.join(raw_dir, d))]
    if len(items) == 1:
        return os.path.join(raw_dir, items[0])
    # Already flat
    return raw_dir


def frame_count_from_folder(folder):
    """Return frame count by checking any available direction subfolder."""
    for d in DIAG_DIRS:
        dp = os.path.join(folder, d)
        if os.path.isdir(dp):
            return len([f for f in os.listdir(dp) if f.endswith(".png")])
    return 0


def organize(extracted_root):
    print("Organizing sprites...")
    os.makedirs(out_dir, exist_ok=True)

    # Clear old PNGs (leave .import files; Godot regenerates them)
    for f in os.listdir(out_dir):
        if f.endswith(".png"):
            os.remove(os.path.join(out_dir, f))

    anim_root = os.path.join(extracted_root, "animations")

    # Bucket animating* folders into idle (8f) / walk (4f)
    idle_folders, walk_folders = [], []
    for name in os.listdir(anim_root):
        folder = os.path.join(anim_root, name)
        if not os.path.isdir(folder):
            continue
        if not (name == "animating" or name.startswith("animating-")):
            continue
        fc = frame_count_from_folder(folder)
        if fc == 8:
            idle_folders.append(folder)
        elif fc == 4:
            walk_folders.append(folder)
        else:
            print(f"  unknown: {name} ({fc}f)")
    print(f"  idle_folders={len(idle_folders)}  walk_folders={len(walk_folders)}")

    # Static rotations (diagonal only)
    rot_dir = os.path.join(extracted_root, "rotations")
    for long, short in DIAG_DIRS.items():
        src = os.path.join(rot_dir, f"{long}.png")
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(out_dir, f"unit_{UNIT_KEY}_{short}.png"))
            print(f"  static {long}")

    # Idle frames — merge from all idle folders (fills missing dirs)
    copied_idle = set()
    for folder in idle_folders:
        for long, short in DIAG_DIRS.items():
            if long in copied_idle:
                continue
            src = os.path.join(folder, long)
            if not os.path.isdir(src):
                continue
            frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
            if not frames:
                continue
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(src, f),
                             os.path.join(out_dir, f"unit_{UNIT_KEY}_idle_{short}_f{i}.png"))
            copied_idle.add(long)
            print(f"  idle {long} ({len(frames)} frames)")

    # Walk frames
    copied_walk = set()
    for folder in walk_folders:
        for long, short in DIAG_DIRS.items():
            if long in copied_walk:
                continue
            src = os.path.join(folder, long)
            if not os.path.isdir(src):
                continue
            frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
            if not frames:
                continue
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(src, f),
                             os.path.join(out_dir, f"unit_{UNIT_KEY}_walk_{short}_f{i}.png"))
            copied_walk.add(long)
            print(f"  walk {long} ({len(frames)} frames)")

    # Attack — find non-animating folder with south/ subdir
    attack_south = None
    for name in os.listdir(anim_root):
        if name.startswith("animating"):
            continue
        south_path = os.path.join(anim_root, name, "south")
        if os.path.isdir(south_path):
            attack_south = south_path
            print(f"  attack folder: {name}")
            break

    if attack_south:
        frames = sorted(f for f in os.listdir(attack_south) if f.endswith(".png"))
        for short in DIAG_DIRS.values():
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(attack_south, f),
                             os.path.join(out_dir, f"unit_{UNIT_KEY}_{ATTACK_ANIM}_{short}_f{i}.png"))
        print(f"  {ATTACK_ANIM}: {len(frames)} frames -> all 4 diagonals")
    else:
        print(f"  WARNING: attack south not found")

    total = len([f for f in os.listdir(out_dir) if f.endswith(".png")])
    print(f"\nDone! {total} PNG files in sprites/")


if __name__ == "__main__":
    if os.path.exists(zip_path):
        os.remove(zip_path)
    download()
    root = extract()
    organize(root)

"""
organize_sand_raider.py

Custom organizer for Sand Raider — its ZIP has multiple idle/walk animation
folders because directions were queued in separate batches.

ZIP structure:
  animating/              — idle: south, east, north, north-east, south-east, south-west, west (8f)
  animating-5312c2f4/    — idle: north-west (8f)
  animating-f53b99ee/    — walk: west (4f)
  animating-fe4a90fb/    — walk: east, north, north-east, north-west, south, south-east, south-west (4f)
  slashing_a_curved...   — attack (south, 9f) → mirrored to all 8 dirs

Run from project root.
"""

import os, shutil

BASE_DIR = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units\sand_raider"
RAW_DIR  = os.path.join(BASE_DIR, "raw", "Sand_Raider")
OUT_DIR  = os.path.join(BASE_DIR, "sprites")

DIR_SHORT = {
    "south": "s", "north": "n", "east": "e", "west": "w",
    "south-east": "se", "south-west": "sw",
    "north-east": "ne", "north-west": "nw",
}

os.makedirs(OUT_DIR, exist_ok=True)

anim_root = os.path.join(RAW_DIR, "animations")

# ── Static rotations ─────────────────────────────────────────────────────────
for d, short in DIR_SHORT.items():
    src = os.path.join(RAW_DIR, "rotations", f"{d}.png")
    if os.path.exists(src):
        dst = os.path.join(OUT_DIR, f"unit_sand_raider_{short}.png")
        shutil.copy2(src, dst)
        print(f"  rotation {d}")

# ── Idle — collect all 8f dirs from every animation folder ───────────────────
idle_collected = {}
for folder in sorted(os.listdir(anim_root)):
    folder_path = os.path.join(anim_root, folder)
    if not os.path.isdir(folder_path):
        continue
    for direction in os.listdir(folder_path):
        dir_path = os.path.join(folder_path, direction)
        if not os.path.isdir(dir_path):
            continue
        frames = sorted([f for f in os.listdir(dir_path) if f.endswith(".png")])
        if len(frames) == 8 and direction in DIR_SHORT:
            idle_collected[direction] = (dir_path, frames)

for direction, (src_path, frames) in sorted(idle_collected.items()):
    short = DIR_SHORT[direction]
    for i, fname in enumerate(frames):
        src = os.path.join(src_path, fname)
        dst = os.path.join(OUT_DIR, f"unit_sand_raider_idle_{short}_f{i}.png")
        shutil.copy2(src, dst)
    print(f"  idle {direction} ({len(frames)} frames)")

# ── Walk — collect all 4f dirs from every animation folder ───────────────────
walk_collected = {}
for folder in sorted(os.listdir(anim_root)):
    folder_path = os.path.join(anim_root, folder)
    if not os.path.isdir(folder_path):
        continue
    for direction in os.listdir(folder_path):
        dir_path = os.path.join(folder_path, direction)
        if not os.path.isdir(dir_path):
            continue
        frames = sorted([f for f in os.listdir(dir_path) if f.endswith(".png")])
        if len(frames) == 4 and direction in DIR_SHORT:
            walk_collected[direction] = (dir_path, frames)

for direction, (src_path, frames) in sorted(walk_collected.items()):
    short = DIR_SHORT[direction]
    for i, fname in enumerate(frames):
        src = os.path.join(src_path, fname)
        dst = os.path.join(OUT_DIR, f"unit_sand_raider_walk_{short}_f{i}.png")
        shutil.copy2(src, dst)
    print(f"  walk {direction} ({len(frames)} frames)")

# ── Classify non-animating folders: attack (south-only) vs death (8-dir) ─────
VALID_DIRS = set(DIR_SHORT.keys())
attack_south = None
death_dirs   = {}

for folder in os.listdir(anim_root):
    if folder.startswith("animating"):
        continue
    folder_path = os.path.join(anim_root, folder)
    if not os.path.isdir(folder_path):
        continue
    subdirs = [d for d in os.listdir(folder_path)
               if os.path.isdir(os.path.join(folder_path, d)) and d in VALID_DIRS]
    if len(subdirs) >= 4:
        for d in subdirs:
            death_dirs[d] = os.path.join(folder_path, d)
        print(f"  found death folder: {folder} ({len(subdirs)} dirs)")
    elif "south" in subdirs and attack_south is None:
        attack_south = os.path.join(folder_path, "south")
        print(f"  found attack folder: {folder}")

# ── Attack (south → mirrored) ─────────────────────────────────────────────────
if attack_south:
    attack_frames = sorted([f for f in os.listdir(attack_south) if f.endswith(".png")])
    for i, fname in enumerate(attack_frames):
        src = os.path.join(attack_south, fname)
        for short in DIR_SHORT.values():
            dst = os.path.join(OUT_DIR, f"unit_sand_raider_sword_slash_{short}_f{i}.png")
            shutil.copy2(src, dst)
    print(f"  attack sword_slash ({len(attack_frames)} frames, mirrored to all 8 dirs)")

# ── Death (all 8 dirs copied directly) ────────────────────────────────────────
if death_dirs:
    for d, src_path in sorted(death_dirs.items()):
        short = DIR_SHORT[d]
        frames = sorted([f for f in os.listdir(src_path) if f.endswith(".png")])
        for i, fname in enumerate(frames):
            shutil.copy2(os.path.join(src_path, fname),
                         os.path.join(OUT_DIR, f"unit_sand_raider_death_{short}_f{i}.png"))
    sample_dir = next(iter(death_dirs.values()))
    sample_frames = [f for f in os.listdir(sample_dir) if f.endswith(".png")]
    print(f"  death: {len(sample_frames)} frames × {len(death_dirs)} dirs")
else:
    print(f"  (no death animation in zip yet)")

total = len(os.listdir(OUT_DIR))
print(f"\nsprites/: {total} files")
print("Done.")

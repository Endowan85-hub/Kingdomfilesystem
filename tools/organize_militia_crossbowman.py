import os, shutil

base_dir  = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units\militia_crossbowman"
raw_base  = os.path.join(base_dir, "raw", "base", "Militia_Crossbowman")
raw_combat = os.path.join(base_dir, "raw", "combat", "raising_crossbow_up")
out       = os.path.join(base_dir, "sprites")

DIR_SHORT = {
    "south": "s", "north": "n", "east": "e", "west": "w",
    "south-east": "se", "south-west": "sw",
    "north-east": "ne", "north-west": "nw"
}

os.makedirs(out, exist_ok=True)

# ── Static rotations ──────────────────────────────────────────────────────────
for d, short in DIR_SHORT.items():
    src = os.path.join(raw_base, "rotations", f"{d}.png")
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(out, f"unit_militia_crossbowman_{short}.png"))
        print(f"  static {d}")

# ── Idle (animating folder, 8 frames/dir) ────────────────────────────────────
for d, short in DIR_SHORT.items():
    src = os.path.join(raw_base, "animations", "animating", d)
    if not os.path.isdir(src):
        continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_militia_crossbowman_idle_{short}_f{i}.png"))
    print(f"  idle {d} ({len(frames)} frames)")

# ── Walk (animating-9b00a918 folder, 4 frames/dir) ───────────────────────────
walk_folder = None
anim_root = os.path.join(raw_base, "animations")
for folder in os.listdir(anim_root):
    if folder.startswith("animating-"):
        walk_folder = os.path.join(anim_root, folder)
        break

if walk_folder:
    for d, short in DIR_SHORT.items():
        src = os.path.join(walk_folder, d)
        if not os.path.isdir(src):
            continue
        frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_militia_crossbowman_walk_{short}_f{i}.png"))
        print(f"  walk {d} ({len(frames)} frames)")

# ── Bow shoot (south only → mirror to all dirs) ───────────────────────────────
shoot_south = None
if os.path.isdir(raw_combat):
    anim_root_c = os.path.join(raw_combat, "animations")
    if os.path.isdir(anim_root_c):
        for folder in os.listdir(anim_root_c):
            south_dir = os.path.join(anim_root_c, folder, "south")
            if os.path.isdir(south_dir):
                shoot_south = south_dir
                break

if shoot_south:
    frames = sorted(f for f in os.listdir(shoot_south) if f.endswith(".png"))
    for short in DIR_SHORT.values():
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(shoot_south, f),
                         os.path.join(out, f"unit_militia_crossbowman_bow_shoot_{short}_f{i}.png"))
    print(f"  bow_shoot all dirs ({len(frames)} frames from south)")
else:
    print("  WARNING: bow_shoot south not found — skipping")

print(f"\nDone! Total files: {len(os.listdir(out))}")

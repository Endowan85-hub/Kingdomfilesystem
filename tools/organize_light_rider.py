import os, shutil

base_dir = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units\light_rider"
raw      = os.path.join(base_dir, "raw", "Light_Rider")
out      = os.path.join(base_dir, "sprites")

DIR_SHORT = {
    "south": "s", "north": "n", "east": "e", "west": "w",
    "south-east": "se", "south-west": "sw",
    "north-east": "ne", "north-west": "nw"
}

os.makedirs(out, exist_ok=True)

# ── Static rotations ──────────────────────────────────────────────────────────
for d, short in DIR_SHORT.items():
    src = os.path.join(raw, "rotations", f"{d}.png")
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(out, f"unit_light_rider_{short}.png"))
        print(f"  static {d}")

# ── Idle & Walk — detect by frame count (idle=8, walk=4) ─────────────────────
# PixelLab ZIP may put walk in 'animating' and idle in 'animating-{hash}' or vice versa.
anim_root = os.path.join(raw, "animations")
anim_plain = os.path.join(anim_root, "animating")

# Count frames in south to identify which folder is which
def _frame_count(folder):
    south = os.path.join(folder, "south")
    if not os.path.isdir(south):
        return 0
    return len([f for f in os.listdir(south) if f.endswith(".png")])

hashed_folder = None
for folder in os.listdir(anim_root):
    if folder.startswith("animating-"):
        hashed_folder = os.path.join(anim_root, folder)
        break

plain_count  = _frame_count(anim_plain)
hashed_count = _frame_count(hashed_folder) if hashed_folder else 0

idle_folder = anim_plain  if plain_count  >= hashed_count else hashed_folder
walk_folder = hashed_folder if plain_count >= hashed_count else anim_plain

print(f"  [detected] animating/={plain_count}f  animating-hash/={hashed_count}f")

for d, short in DIR_SHORT.items():
    src = os.path.join(idle_folder, d)
    if not os.path.isdir(src):
        continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_light_rider_idle_{short}_f{i}.png"))
    print(f"  idle {d} ({len(frames)} frames)")

if walk_folder:
    for d, short in DIR_SHORT.items():
        src = os.path.join(walk_folder, d)
        if not os.path.isdir(src):
            continue
        frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_light_rider_walk_{short}_f{i}.png"))
        print(f"  walk {d} ({len(frames)} frames)")

# ── Sword slash (south only → mirror to all dirs) ────────────────────────────
slash_folder = None
for folder in os.listdir(anim_root):
    if folder.startswith("swinging"):
        south_dir = os.path.join(anim_root, folder, "south")
        if os.path.isdir(south_dir):
            slash_folder = south_dir
            break

if slash_folder:
    frames = sorted(f for f in os.listdir(slash_folder) if f.endswith(".png"))
    for short in DIR_SHORT.values():
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(slash_folder, f),
                         os.path.join(out, f"unit_light_rider_sword_slash_{short}_f{i}.png"))
    print(f"  sword_slash all dirs ({len(frames)} frames from south)")
else:
    print("  WARNING: sword_slash south not found — skipping")

print(f"\nDone! Total files: {len(os.listdir(out))}")

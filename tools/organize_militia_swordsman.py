import os, shutil

base = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units\militia_swordsman"
raw  = os.path.join(base, "raw", "Militia_Swordsman")
out  = os.path.join(base, "sprites")

DIR_SHORT = {
    "south": "s", "north": "n", "east": "e", "west": "w",
    "south-east": "se", "south-west": "sw",
    "north-east": "ne", "north-west": "nw"
}

os.makedirs(out, exist_ok=True)

# Static rotations
for d, short in DIR_SHORT.items():
    src = os.path.join(raw, "rotations", f"{d}.png")
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(out, f"unit_militia_swordsman_{short}.png"))
        print(f"  static {d}")

# Idle = 'animating' folder (8 frames/dir)
for d, short in DIR_SHORT.items():
    src = os.path.join(raw, "animations", "animating", d)
    if not os.path.isdir(src): continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_militia_swordsman_idle_{short}_f{i}.png"))
    print(f"  idle {d} ({len(frames)} frames)")

# Walk = 'animating-fdc3f786' folder (4 frames/dir)
for d, short in DIR_SHORT.items():
    src = os.path.join(raw, "animations", "animating-fdc3f786", d)
    if not os.path.isdir(src): continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_militia_swordsman_walk_{short}_f{i}.png"))
    print(f"  walk {d} ({len(frames)} frames)")

# Sword slash = south only, copy to all dirs as fallback
slash_folders = [d for d in os.listdir(os.path.join(raw, "animations")) if d.startswith("slashing")]
if slash_folders:
    slash_dir = os.path.join(raw, "animations", slash_folders[0], "south")
    if os.path.isdir(slash_dir):
        frames = sorted(f for f in os.listdir(slash_dir) if f.endswith(".png"))
        for short in DIR_SHORT.values():
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(slash_dir, f), os.path.join(out, f"unit_militia_swordsman_sword_slash_{short}_f{i}.png"))
        print(f"  sword_slash all dirs ({len(frames)} frames from south)")

print(f"\nDone! Total files: {len(os.listdir(out))}")

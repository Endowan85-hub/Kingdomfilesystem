import os, shutil

base = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units\harpoon_fighter"
raw  = os.path.join(base, "raw", "Harpoon_Fighter")
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
        shutil.copy2(src, os.path.join(out, f"unit_harpoon_fighter_{short}.png"))
        print(f"  static {d}")

# Idle = 'animating' folder (8 frames/dir)
anim_dir = os.path.join(raw, "animations", "animating")
for d, short in DIR_SHORT.items():
    src = os.path.join(anim_dir, d)
    if not os.path.isdir(src): continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_harpoon_fighter_idle_{short}_f{i}.png"))
    print(f"  idle {d} ({len(frames)} frames)")

# Walk = 'animating-7586656e' folder (4 frames/dir)
walk_dir = os.path.join(raw, "animations", "animating-7586656e")
for d, short in DIR_SHORT.items():
    src = os.path.join(walk_dir, d)
    if not os.path.isdir(src): continue
    frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    for i, f in enumerate(frames):
        shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_harpoon_fighter_walk_{short}_f{i}.png"))
    print(f"  walk {d} ({len(frames)} frames)")

# Spear thrust = pro version, south only — copy to all dirs as fallback
thrust_dir = os.path.join(raw, "animations", "thrusting_harpoon_forward_with_a_quick_powerful_ja-ae7dabf9", "south")
if os.path.isdir(thrust_dir):
    frames = sorted(f for f in os.listdir(thrust_dir) if f.endswith(".png"))
    for short in DIR_SHORT.values():
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(thrust_dir, f), os.path.join(out, f"unit_harpoon_fighter_spear_thrust_{short}_f{i}.png"))
    print(f"  spear_thrust all dirs ({len(frames)} frames from south)")

print(f"\nDone! Total files: {len(os.listdir(out))}")

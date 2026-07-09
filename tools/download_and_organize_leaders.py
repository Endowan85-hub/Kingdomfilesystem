"""
Download ZIPs from PixelLab and organize sprites for story leaders.
Run from any directory — paths are absolute.

File output: Art/leaders/{house_id}/sprites/
Naming convention (long direction codes):
  {house_id}_{direction}.png            — static rotation
  {house_id}_idle_{direction}_f{n}.png  — idle (8 frames)
  {house_id}_walk_{direction}_f{n}.png  — walk (4 frames)
  {house_id}_{attack_anim}_{direction}_f{n}.png — attack (south mirrored to all 8 dirs)
"""

import os, shutil, zipfile, urllib.request

API_KEY  = "5ecba419-72b5-49b9-891f-ea46597c3065"
BASE_DIR = r"C:\Users\Patrick\dev\kingdom-(test)\Art\leaders"
TOOLS_DIR = r"C:\Users\Patrick\dev\kingdom-(test)\tools"

DIRS = ["south", "north", "east", "west", "south-east", "south-west", "north-east", "north-west"]

# (house_id, character_id, attack_anim)
LEADERS = [
    ("house_outsider",  "da577daa-7f45-4f17-86b5-59f6df03159b", "sword_slash"),
    ("house_provinces", "048a9975-3718-4ef0-adf0-2726ee2298b9", "spear_thrust"),
    ("house_roads",     "cbf0dffd-3cec-4099-a48c-2a383a1fc644", "mace_swing"),
    ("house_crown",     "320e949f-cfd4-4c09-9696-5132e05cb5ce", "sword_slash"),
    ("house_counsel",   "2bec9164-253b-4355-9b90-6e1013df60a8", "mace_swing"),
    ("house_war",       "35796728-3c36-4bc6-afab-a05938821a5f", "sword_slash"),
    ("house_blood",     "86f0d55e-50fd-4510-bcc3-39e2399e17e4", "sword_slash"),
    ("house_faith",     "c607ad5d-e791-4e07-ad3e-d5aa4f250eb2", "mace_swing"),
    ("house_shadows",   "260ca3c7-a917-46b5-8953-3ec4ab52e6a9", "sword_slash"),
    ("house_diplomacy", "894aa5b8-739f-4429-b3f7-58a5e2dd993f", "mace_swing"),
    ("house_frontier",  "4aca7c1b-c1cd-483e-99d8-ac4756404dda", "spear_thrust"),
    ("house_law",       "8dbf3436-e40e-4bd5-a107-5e449fd12676", "mace_swing"),
    ("house_strategy",  "54a31af9-e3c4-456e-92e7-e2091bb8b863", "sword_slash"),
    ("house_coin",      "3c465acd-7af8-4341-ad79-0c9c94579824", "spear_thrust"),
    ("house_people",    "8c9cce63-8d31-4519-a059-271feb4aed64", "spear_thrust"),
]


def _frame_count(folder):
    if not folder or not os.path.isdir(folder):
        return 0
    south = os.path.join(folder, "south")
    if not os.path.isdir(south):
        return 0
    return len([f for f in os.listdir(south) if f.endswith(".png")])


def download_zip(character_id, dest_path):
    url = f"https://api.pixellab.ai/mcp/characters/{character_id}/download"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as f:
        f.write(resp.read())


def organize_leader(house_id, attack_anim, raw):
    out = os.path.join(BASE_DIR, house_id, "sprites")
    os.makedirs(out, exist_ok=True)

    # ── Static rotations ──────────────────────────────────────────────────────
    for d in DIRS:
        src = os.path.join(raw, "rotations", f"{d}.png")
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(out, f"{house_id}_{d}.png"))

    # ── Idle & Walk — detect by frame count across ALL animating folders ───────
    # idle = 8 frames per dir, walk = 4 frames per dir
    # PixelLab sometimes generates missing dirs in separate batches (extra folders)
    anim_root = os.path.join(raw, "animations")

    # Collect all animating-* folders plus the plain "animating" folder
    all_anim_folders = []
    for folder in os.listdir(anim_root):
        if folder == "animating" or folder.startswith("animating-"):
            all_anim_folders.append(os.path.join(anim_root, folder))

    # Bucket each folder as idle (8f), walk (4f), or unknown
    idle_folders = []
    walk_folders = []
    for folder in all_anim_folders:
        # Count frames from any available direction
        count = 0
        for d in DIRS:
            d_path = os.path.join(folder, d)
            if os.path.isdir(d_path):
                count = len([f for f in os.listdir(d_path) if f.endswith(".png")])
                break
        if count == 8:
            idle_folders.append(folder)
        elif count == 4:
            walk_folders.append(folder)
        else:
            print(f"    unknown anim folder: {os.path.basename(folder)} ({count}f)")

    print(f"    idle_folders={len(idle_folders)}  walk_folders={len(walk_folders)}")

    # Copy idle frames — merge from all idle folders (fills in missing dirs)
    copied_idle = set()
    for folder in idle_folders:
        for d in DIRS:
            if d in copied_idle:
                continue
            src = os.path.join(folder, d)
            if not os.path.isdir(src):
                continue
            frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
            if not frames:
                continue
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(src, f), os.path.join(out, f"{house_id}_idle_{d}_f{i}.png"))
            copied_idle.add(d)
            print(f"    idle {d} ({len(frames)} frames)")

    # Copy walk frames
    for folder in walk_folders:
        for d in DIRS:
            src = os.path.join(folder, d)
            if not os.path.isdir(src):
                continue
            frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
            if not frames:
                continue
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(src, f), os.path.join(out, f"{house_id}_walk_{d}_f{i}.png"))
            print(f"    walk {d} ({len(frames)} frames)")

    # ── Classify non-animating folders as attack (south-only) or death (8-dir) ─
    attack_south = None
    death_dirs   = {}
    VALID_DIRS   = set(DIRS)

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
            print(f"    found death folder: {folder} ({len(subdirs)} dirs)")
        elif "south" in subdirs and attack_south is None:
            attack_south = os.path.join(folder_path, "south")
            print(f"    found attack folder: {folder}")

    # ── Attack (south → mirrored) ────────────────────────────────────────────
    if attack_south:
        frames = sorted(f for f in os.listdir(attack_south) if f.endswith(".png"))
        for d in DIRS:
            for i, f in enumerate(frames):
                shutil.copy2(
                    os.path.join(attack_south, f),
                    os.path.join(out, f"{house_id}_{attack_anim}_{d}_f{i}.png")
                )
        print(f"    {attack_anim}: {len(frames)} frames mirrored to all 8 dirs")
    else:
        print(f"    WARNING: {attack_anim} south not found")

    # ── Death (all 8 dirs copied directly) ──────────────────────────────────
    if death_dirs:
        for d, src_path in sorted(death_dirs.items()):
            frames = sorted(f for f in os.listdir(src_path) if f.endswith(".png"))
            for i, f in enumerate(frames):
                shutil.copy2(
                    os.path.join(src_path, f),
                    os.path.join(out, f"{house_id}_death_{d}_f{i}.png")
                )
        sample_dir = next(iter(death_dirs.values()))
        sample_frames = [f for f in os.listdir(sample_dir) if f.endswith(".png")]
        print(f"    death: {len(sample_frames)} frames × {len(death_dirs)} dirs")
    else:
        print(f"    (no death animation in zip yet)")

    total = len(os.listdir(out))
    print(f"    sprites/: {total} files")
    return total


def process_leader(house_id, character_id, attack_anim):
    leader_dir = os.path.join(BASE_DIR, house_id)
    raw_dir    = os.path.join(leader_dir, "raw", house_id)
    zip_path   = os.path.join(TOOLS_DIR, f"{house_id}.zip")

    print(f"\n{'='*50}")
    print(f"  {house_id}  ({attack_anim})")
    print(f"{'='*50}")

    # Download
    if not os.path.exists(zip_path):
        print(f"  Downloading...")
        try:
            download_zip(character_id, zip_path)
            print(f"  Downloaded: {os.path.getsize(zip_path)//1024} KB")
        except Exception as e:
            print(f"  ERROR downloading: {e}")
            return False
    else:
        print(f"  ZIP already exists ({os.path.getsize(zip_path)//1024} KB) — skipping download")

    # Extract
    if not os.path.isdir(raw_dir):
        print(f"  Extracting...")
        os.makedirs(os.path.join(leader_dir, "raw"), exist_ok=True)
        with zipfile.ZipFile(zip_path, "r") as z:
            z.extractall(os.path.join(leader_dir, "raw"))

        raw_parent = os.path.join(leader_dir, "raw")
        if not os.path.isdir(raw_dir):
            candidates = [d for d in os.listdir(raw_parent) if os.path.isdir(os.path.join(raw_parent, d))]
            if len(candidates) == 1:
                actual = os.path.join(raw_parent, candidates[0])
                os.rename(actual, raw_dir)
                print(f"  Renamed '{candidates[0]}' -> '{house_id}'")
            else:
                print(f"  WARNING: expected raw/{house_id}/ not found. Got: {candidates}")
                return False
        print(f"  Extracted OK")
    else:
        print(f"  raw/{house_id}/ already exists — skipping extract")

    # Organize
    print(f"  Organizing sprites...")
    organize_leader(house_id, attack_anim, raw_dir)
    return True


if __name__ == "__main__":
    import sys

    filter_key = sys.argv[1] if len(sys.argv) > 1 else None

    success, failed = [], []
    for house_id, character_id, attack_anim in LEADERS:
        if filter_key and house_id != filter_key:
            continue
        ok = process_leader(house_id, character_id, attack_anim)
        (success if ok else failed).append(house_id)

    print(f"\n{'='*50}")
    print(f"Done. {len(success)} succeeded, {len(failed)} failed.")
    if failed:
        print(f"Failed: {failed}")

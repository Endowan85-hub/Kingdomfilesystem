"""
Download ZIPs from PixelLab and organize sprites for all 24 tier 1 units.
Run from any directory — paths are absolute.
"""

import os, shutil, zipfile, urllib.request

API_KEY    = "5ecba419-72b5-49b9-891f-ea46597c3065"
BASE_DIR   = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units"
TOOLS_DIR  = r"C:\Users\Patrick\dev\kingdom-(test)\tools"

DIR_SHORT = {
    "south": "s", "north": "n", "east": "e", "west": "w",
    "south-east": "se", "south-west": "sw",
    "north-east": "ne", "north-west": "nw"
}

UNITS = [
    # (sprite_key, zip_folder_name, attack_anim, character_id)
    ("hunter",            "Hunter",            "bow_shoot",   "73cc2ee2-c92e-4d80-b93c-4cf81a802848"),
    ("forest_skirmisher", "Forest_Skirmisher", "sword_slash", "e2443d78-fc37-4277-8a4b-61c7f3daa435"),
    ("forest_rider",      "Forest_Rider",      "sword_slash", "58eeabb8-64a9-42d6-a168-2844a7692f79"),
    ("mountain_guard",    "Mountain_Guard",    "sword_slash", "d9a17153-6dc0-4f63-aed4-c1fd434fb5cf"),
    ("stonebreaker",      "Stonebreaker",      "sword_slash", "25d62eb0-ebcc-49ea-a711-a4ea1547f21f"),
    ("sand_raider",       "Sand_Raider",       "sword_slash", "4420d2f6-41bf-4291-9d43-ee115cd6f9c2"),
    ("caravan_guard",     "Caravan_Guard",     "sword_slash", "9cfd3b45-282a-463c-9855-d147810f705f"),
    ("dune_archer",       "Dune_Archer",       "bow_shoot",   "523aeb1b-47fa-499f-8d64-ba0f5dd91966"),
    ("dust_crusher",      "Dust_Crusher",      "sword_slash", "d705aaaf-8ddb-48d9-a89b-9eb26350ba43"),
    ("ice_warrior",       "Ice_Warrior",       "sword_slash", "f4efda7c-0e19-4577-aa04-362b878211ee"),
    ("ice_archer",        "Ice_Archer",        "bow_shoot",   "09e27e82-200e-4e12-a85e-05a55bc29b9f"),
    ("northern_raider",   "Northern_Raider",   "sword_slash", "747e5d6c-4ca6-4661-87a2-844d4822abea"),
    ("bog_fighter",       "Bog_Fighter",       "sword_slash", "5f4339b5-cad1-40d8-9c83-7e430e400e72"),
    ("reed_archer",       "Reed_Archer",       "bow_shoot",   "e45a14a1-223b-4d17-93d9-e4887d6f68d1"),
    ("swamp_ambusher",    "Swamp_Ambusher",    "sword_slash", "65a42cd7-4bed-4c96-8cfe-09f8b64c2e50"),
    ("marine",            "Marine",            "sword_slash", "029d2ffe-bea5-4526-ac38-b9b42bc78d2a"),
    ("boarding_infantry",   "Boarding_Infantry",   "sword_slash",  "b6a14927-53a1-405e-8d9a-941afefe22ab"),
    ("dockhand_brawler",   "Dockhand_Brawler",    "sword_slash",  "23684615-3d50-4c1b-a520-0b1b1281fedf"),
    # Plains units (earlier sessions)
    ("militia_swordsman",  "Militia_Swordsman",   "sword_slash",  "40b2ad26-1bc8-4268-9a4a-c76c975ba7d7"),
    ("militia_spearman",   "Militia_Spearman",    "spear_thrust", "71e6de30-925b-4ecf-944f-dff3c00634e1"),
    ("militia_crossbowman","Militia_Crossbowman", "bow_shoot",    "d1e154d2-1105-4297-8507-f91ab0866486"),
    ("light_rider",        "Light_Rider",         "sword_slash",  "c8c7045d-973f-4036-a2e0-850c8ea25630"),
    ("mountain_pikeman",   "Mountain_Pikeman",    "spear_thrust", "90f92d45-bdec-47e1-aac8-2aad63334c89"),
    ("harpoon_fighter",    "Harpoon_Fighter",     "spear_thrust", "0529d910-95bc-4a25-b773-32c5b280e3f9"),
]


def _frame_count(folder):
    south = os.path.join(folder, "south")
    if not os.path.isdir(south):
        return 0
    return len([f for f in os.listdir(south) if f.endswith(".png")])


def download_zip(character_id, dest_path):
    url = f"https://api.pixellab.ai/mcp/characters/{character_id}/download"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as f:
        f.write(resp.read())


def organize_unit(sprite_key, zip_folder_name, attack_anim, raw):
    out = os.path.join(BASE_DIR, sprite_key, "sprites")
    os.makedirs(out, exist_ok=True)

    # ── Static rotations ──────────────────────────────────────────────────────
    for d, short in DIR_SHORT.items():
        src = os.path.join(raw, "rotations", f"{d}.png")
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(out, f"unit_{sprite_key}_{short}.png"))

    # ── Idle & Walk — detect by frame count (idle=8f, walk=4f) ───────────────
    anim_root  = os.path.join(raw, "animations")
    anim_plain = os.path.join(anim_root, "animating")

    hashed_folder = None
    for folder in os.listdir(anim_root):
        if folder.startswith("animating-"):
            hashed_folder = os.path.join(anim_root, folder)
            break

    plain_count  = _frame_count(anim_plain)
    hashed_count = _frame_count(hashed_folder) if hashed_folder else 0
    print(f"    animating/={plain_count}f  animating-hash/={hashed_count}f")

    idle_folder = anim_plain    if plain_count >= hashed_count else hashed_folder
    walk_folder = hashed_folder if plain_count >= hashed_count else anim_plain

    for d, short in DIR_SHORT.items():
        src = os.path.join(idle_folder, d)
        if not os.path.isdir(src):
            continue
        frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
        for i, f in enumerate(frames):
            shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_{sprite_key}_idle_{short}_f{i}.png"))
        print(f"    idle {d} ({len(frames)} frames)")

    if walk_folder:
        for d, short in DIR_SHORT.items():
            src = os.path.join(walk_folder, d)
            if not os.path.isdir(src):
                continue
            frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
            for i, f in enumerate(frames):
                shutil.copy2(os.path.join(src, f), os.path.join(out, f"unit_{sprite_key}_walk_{short}_f{i}.png"))
            print(f"    walk {d} ({len(frames)} frames)")

    # ── Classify non-animating folders as attack (south-only) or death (8-dir) ─
    attack_south = None
    death_dirs   = {}   # direction -> folder path

    VALID_DIRS = set(DIR_SHORT.keys())
    for folder in os.listdir(anim_root):
        if folder.startswith("animating"):
            continue
        folder_path = os.path.join(anim_root, folder)
        if not os.path.isdir(folder_path):
            continue
        subdirs = [d for d in os.listdir(folder_path)
                   if os.path.isdir(os.path.join(folder_path, d)) and d in VALID_DIRS]
        if len(subdirs) >= 4:
            # Multi-directional → death animation
            for d in subdirs:
                death_dirs[d] = os.path.join(folder_path, d)
            print(f"    found death folder: {folder} ({len(subdirs)} dirs)")
        elif "south" in subdirs and attack_south is None:
            # South-only → attack, mirror to all dirs
            attack_south = os.path.join(folder_path, "south")
            print(f"    found attack folder: {folder}")

    # ── Attack (south → mirrored) ────────────────────────────────────────────
    if attack_south:
        frames = sorted(f for f in os.listdir(attack_south) if f.endswith(".png"))
        for short in DIR_SHORT.values():
            for i, f in enumerate(frames):
                shutil.copy2(
                    os.path.join(attack_south, f),
                    os.path.join(out, f"unit_{sprite_key}_{attack_anim}_{short}_f{i}.png")
                )
        print(f"    {attack_anim}: {len(frames)} frames mirrored to all 8 dirs")
    else:
        print(f"    WARNING: {attack_anim} south not found")

    # ── Death (all 8 dirs copied directly) ──────────────────────────────────
    if death_dirs:
        for d, src_path in sorted(death_dirs.items()):
            short = DIR_SHORT[d]
            frames = sorted(f for f in os.listdir(src_path) if f.endswith(".png"))
            for i, f in enumerate(frames):
                shutil.copy2(
                    os.path.join(src_path, f),
                    os.path.join(out, f"unit_{sprite_key}_death_{short}_f{i}.png")
                )
        sample_dir = next(iter(death_dirs.values()))
        sample_frames = [f for f in os.listdir(sample_dir) if f.endswith(".png")]
        print(f"    death: {len(sample_frames)} frames × {len(death_dirs)} dirs")
    else:
        print(f"    (no death animation in zip yet)")

    total = len(os.listdir(out))
    print(f"    sprites/: {total} files")
    return total


def process_unit(sprite_key, zip_folder_name, attack_anim, character_id):
    unit_dir = os.path.join(BASE_DIR, sprite_key)
    raw_dir  = os.path.join(unit_dir, "raw", zip_folder_name)
    zip_path = os.path.join(TOOLS_DIR, f"{sprite_key}.zip")

    print(f"\n{'='*50}")
    print(f"  {sprite_key}  ({attack_anim})")
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
        print(f"  Extracting to raw/{zip_folder_name}/...")
        os.makedirs(os.path.join(unit_dir, "raw"), exist_ok=True)
        with zipfile.ZipFile(zip_path, "r") as z:
            z.extractall(os.path.join(unit_dir, "raw"))

        # PixelLab may use the display name (spaces) instead of underscores.
        # Try to find the extracted folder if the expected name isn't there.
        raw_parent = os.path.join(unit_dir, "raw")
        if not os.path.isdir(raw_dir):
            candidates = [d for d in os.listdir(raw_parent) if os.path.isdir(os.path.join(raw_parent, d))]
            if len(candidates) == 1:
                actual = os.path.join(raw_parent, candidates[0])
                os.rename(actual, raw_dir)
                print(f"  Renamed '{candidates[0]}' → '{zip_folder_name}'")
            else:
                print(f"  WARNING: expected raw/{zip_folder_name}/ not found after extract. Got: {candidates}")
                return False
        print(f"  Extracted OK")
    else:
        print(f"  raw/{zip_folder_name}/ already exists — skipping extract")

    # Organize
    print(f"  Organizing sprites...")
    organize_unit(sprite_key, zip_folder_name, attack_anim, raw_dir)
    return True


if __name__ == "__main__":
    import sys

    # Optionally pass a sprite_key to process just one unit: python script.py hunter
    filter_key = sys.argv[1] if len(sys.argv) > 1 else None

    success, failed = [], []
    for sprite_key, zip_folder_name, attack_anim, character_id in UNITS:
        if filter_key and sprite_key != filter_key:
            continue
        ok = process_unit(sprite_key, zip_folder_name, attack_anim, character_id)
        (success if ok else failed).append(sprite_key)

    print(f"\n{'='*50}")
    print(f"Done. {len(success)} succeeded, {len(failed)} failed.")
    if failed:
        print(f"Failed: {failed}")

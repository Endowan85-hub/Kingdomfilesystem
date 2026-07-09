"""
Download corpse (dead) sprites for all 39 characters (24 units + 15 leaders).
Calls the PixelLab API to find the "dead" animation, then downloads the last
south frame directly as the static dead sprite — no ZIP required.

Usage:
  python download_corpse_sprites.py          # all characters
  python download_corpse_sprites.py hunter   # one unit by sprite_key
  python download_corpse_sprites.py house_war  # one leader by house_id
"""

import os, sys, json, zipfile, shutil, urllib.request, tempfile

API_KEY         = "5ecba419-72b5-49b9-891f-ea46597c3065"
BASE_URL        = "https://api.pixellab.ai/mcp"
BASE_DIR_UNITS  = r"C:\Users\Patrick\dev\kingdom-(test)\Art\units"
BASE_DIR_LEADERS= r"C:\Users\Patrick\dev\kingdom-(test)\Art\leaders"
TOOLS_DIR       = r"C:\Users\Patrick\dev\kingdom-(test)\tools"

# The action_description we used, truncated as PixelLab does for folder names
DEAD_FOLDER_PREFIX = "lying_completely_flat"

# (sprite_key, character_id)
UNITS = [
    ("hunter",            "73cc2ee2-c92e-4d80-b93c-4cf81a802848"),
    ("forest_skirmisher", "e2443d78-fc37-4277-8a4b-61c7f3daa435"),
    ("forest_rider",      "58eeabb8-64a9-42d6-a168-2844a7692f79"),
    ("mountain_guard",    "d9a17153-6dc0-4f63-aed4-c1fd434fb5cf"),
    ("stonebreaker",      "25d62eb0-ebcc-49ea-a711-a4ea1547f21f"),
    ("sand_raider",       "4420d2f6-41bf-4291-9d43-ee115cd6f9c2"),
    ("caravan_guard",     "9cfd3b45-282a-463c-9855-d147810f705f"),
    ("dune_archer",       "523aeb1b-47fa-499f-8d64-ba0f5dd91966"),
    ("dust_crusher",      "d705aaaf-8ddb-48d9-a89b-9eb26350ba43"),
    ("ice_warrior",       "f4efda7c-0e19-4577-aa04-362b878211ee"),
    ("ice_archer",        "09e27e82-200e-4e12-a85e-05a55bc29b9f"),
    ("northern_raider",   "747e5d6c-4ca6-4661-87a2-844d4822abea"),
    ("bog_fighter",       "5f4339b5-cad1-40d8-9c83-7e430e400e72"),
    ("reed_archer",       "e45a14a1-223b-4d17-93d9-e4887d6f68d1"),
    ("swamp_ambusher",    "65a42cd7-4bed-4c96-8cfe-09f8b64c2e50"),
    ("marine",            "029d2ffe-bea5-4526-ac38-b9b42bc78d2a"),
    ("boarding_infantry", "b6a14927-53a1-405e-8d9a-941afefe22ab"),
    ("dockhand_brawler",  "23684615-3d50-4c1b-a520-0b1b1281fedf"),
    ("militia_swordsman", "40b2ad26-1bc8-4268-9a4a-c76c975ba7d7"),
    ("militia_spearman",  "71e6de30-925b-4ecf-944f-dff3c00634e1"),
    ("militia_crossbowman","d1e154d2-1105-4297-8507-f91ab0866486"),
    ("light_rider",       "c8c7045d-973f-4036-a2e0-850c8ea25630"),
    ("mountain_pikeman",  "90f92d45-bdec-47e1-aac8-2aad63334c89"),
    ("harpoon_fighter",   "0529d910-95bc-4a25-b773-32c5b280e3f9"),
]

# (house_id, character_id)
LEADERS = [
    ("house_outsider",  "da577daa-7f45-4f17-86b5-59f6df03159b"),
    ("house_provinces", "048a9975-3718-4ef0-adf0-2726ee2298b9"),
    ("house_roads",     "cbf0dffd-3cec-4099-a48c-2a383a1fc644"),
    ("house_crown",     "320e949f-cfd4-4c09-9696-5132e05cb5ce"),
    ("house_counsel",   "2bec9164-253b-4355-9b90-6e1013df60a8"),
    ("house_war",       "35796728-3c36-4bc6-afab-a05938821a5f"),
    ("house_blood",     "86f0d55e-50fd-4510-bcc3-39e2399e17e4"),
    ("house_faith",     "c607ad5d-e791-4e07-ad3e-d5aa4f250eb2"),
    ("house_shadows",   "260ca3c7-a917-46b5-8953-3ec4ab52e6a9"),
    ("house_diplomacy", "894aa5b8-739f-4429-b3f7-58a5e2dd993f"),
    ("house_frontier",  "4aca7c1b-c1cd-483e-99d8-ac4756404dda"),
    ("house_law",       "8dbf3436-e40e-4bd5-a107-5e449fd12676"),
    ("house_strategy",  "54a31af9-e3c4-456e-92e7-e2091bb8b863"),
    ("house_coin",      "3c465acd-7af8-4341-ad79-0c9c94579824"),
    ("house_people",    "8c9cce63-8d31-4519-a059-271feb4aed64"),
]


def download_zip(character_id, dest_path):
    url = f"{BASE_URL}/characters/{character_id}/download"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as f:
        f.write(resp.read())


def find_dead_south_last_frame_in_zip(zip_path):
    """
    Opens the ZIP and finds the 'lying_completely_flat' animation folder,
    then returns the bytes of the last south frame.
    """
    with zipfile.ZipFile(zip_path, "r") as z:
        names = z.namelist()

        # Find south files under the dead folder
        south_files = [
            n for n in names
            if DEAD_FOLDER_PREFIX in n and "/south/" in n and n.endswith(".png")
        ]

        if not south_files:
            all_anim_folders = sorted(set(
                n.split("/")[1] for n in names if n.startswith(("Hunter/animations/", "animations/"))
                and len(n.split("/")) > 2
            ))
            return None, f"no dead south frames found. Anim folders: {all_anim_folders[:10]}"

        south_files.sort()
        last = south_files[-1]
        return z.read(last), None


def process(key, character_id, sprites_dir, out_filename):
    print(f"\n{'='*50}")
    print(f"  {key}")
    print(f"{'='*50}")

    zip_path = os.path.join(TOOLS_DIR, f"{key}_corpse.zip")

    print(f"  Downloading...")
    try:
        download_zip(character_id, zip_path)
        print(f"  Downloaded: {os.path.getsize(zip_path)//1024} KB")
    except Exception as e:
        print(f"  ERROR downloading: {e}")
        return False

    frame_data, err = find_dead_south_last_frame_in_zip(zip_path)
    try:
        os.remove(zip_path)
    except Exception:
        pass

    if frame_data is None:
        print(f"  ERROR: {err}")
        return False

    os.makedirs(sprites_dir, exist_ok=True)
    out_path = os.path.join(sprites_dir, out_filename)
    with open(out_path, "wb") as f:
        f.write(frame_data)
    print(f"  Saved: {out_filename} ({len(frame_data)} bytes)")
    return True


if __name__ == "__main__":
    filter_key = sys.argv[1] if len(sys.argv) > 1 else None

    success, failed = [], []

    for sprite_key, character_id in UNITS:
        if filter_key and sprite_key != filter_key:
            continue
        sprites_dir = os.path.join(BASE_DIR_UNITS, sprite_key, "sprites")
        out_filename = f"unit_{sprite_key}_dead.png"
        ok = process(sprite_key, character_id, sprites_dir, out_filename)
        (success if ok else failed).append(sprite_key)

    for house_id, character_id in LEADERS:
        if filter_key and house_id != filter_key:
            continue
        sprites_dir = os.path.join(BASE_DIR_LEADERS, house_id, "sprites")
        out_filename = f"{house_id}_dead.png"
        ok = process(house_id, character_id, sprites_dir, out_filename)
        (success if ok else failed).append(house_id)

    print(f"\n{'='*50}")
    print(f"Done. {len(success)} succeeded, {len(failed)} failed.")
    if failed:
        print(f"Failed: {failed}")

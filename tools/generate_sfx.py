"""
ElevenLabs SFX generator for Kingdom (TEST)
Usage: python generate_sfx.py
Saves .mp3 files to Audio/sfx/ relative to project root
"""

import urllib.request
import urllib.error
import json
import os
import time

API_KEY = "sk_39f56d61cb5f7385c464b01f00b3d49539627e11898dcbfb"
API_URL = "https://api.elevenlabs.io/v1/sound-generation"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Audio", "sfx")

SOUNDS = [
    ("sword_clash",        "metal swords clashing together, sharp ringing impact"),
    ("arrow_hit",          "arrow thudding into wood, short impact"),
    ("battle_horn",        "deep medieval war horn blowing, single long blast"),
    ("siege_drum",         "heavy military drums beating slow and ominous"),
    ("province_select",    "soft parchment rustle, map selection click"),
    ("province_hover",     "quiet dry paper brush, very short"),
    ("march_footsteps",    "armored soldiers marching on dirt road, rhythmic"),
    ("victory_fanfare",    "short triumphant medieval brass fanfare"),
    ("defeat_sting",       "low dark descending brass sting, grim and final"),
    ("door_wooden_open",   "heavy wooden castle door creaking open slowly"),
    ("coin_drop",          "handful of gold coins dropping onto a wooden table"),
    ("fire_crackling",     "campfire crackling softly, warm and ambient, loopable"),
]

def generate(name, description):
    payload = json.dumps({
        "text": description,
        "duration_seconds": None,
        "prompt_influence": 0.3
    }).encode("utf-8")

    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "xi-api-key": API_KEY,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg"
        }
    )

    print(f"  Generating: {name} ...")
    try:
        with urllib.request.urlopen(req) as resp:
            audio = resp.read()
        out_path = os.path.join(OUT_DIR, f"{name}.mp3")
        with open(out_path, "wb") as f:
            f.write(audio)
        print(f"  Saved: {out_path} ({len(audio)//1024}kb)")
        return True
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"  ERROR {e.code}: {body}")
        return False


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Output dir: {OUT_DIR}\n")

    for name, desc in SOUNDS:
        ok = generate(name, desc)
        if ok:
            time.sleep(0.5)

    print("\nDone.")

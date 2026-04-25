#!/usr/bin/env python3
"""
normalize_sprites.py
====================
Pads every sprite PNG under Art/ to a 256x256 canvas.

Each character is:
  - Cropped to its non-transparent bounding box
  - Centered horizontally
  - Anchored so the bottom of the character sits FOOT_MARGIN px above the canvas bottom
    (consistent foot grounding regardless of how much empty space PixelLab added)

Usage:
  python tools/normalize_sprites.py --dry-run   # preview only, nothing written
  python tools/normalize_sprites.py             # process all sprites in Art/

Options:
  --path PATH    Override the root folder to scan (default: Art/ next to this script)
  --canvas N     Output canvas size in pixels (default: 256)
  --margin N     Pixels from canvas bottom to character feet (default: 8)
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is not installed. Run:  pip install Pillow")
    sys.exit(1)

CANVAS_DEFAULT = 256
MARGIN_DEFAULT = 8   # px from bottom of canvas to feet — small shadow gap


def normalize_sprite(path: Path, canvas_size: int, foot_margin: int, dry_run: bool) -> str:
    img = Image.open(path).convert("RGBA")
    orig_w, orig_h = img.size

    if orig_w == canvas_size and orig_h == canvas_size:
        return f"SKIP  (already {canvas_size}x{canvas_size})  {path.name}"

    bbox = img.getbbox()
    if bbox is None:
        return f"SKIP  (fully transparent)  {path.name}"

    char_w = bbox[2] - bbox[0]
    char_h = bbox[3] - bbox[1]

    if char_w > canvas_size or char_h > canvas_size:
        return (
            f"WARN  character {char_w}x{char_h} exceeds canvas {canvas_size}x{canvas_size}"
            f" -- skipped  {path.name}"
        )

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # Center horizontally; anchor bottom of character content to foot position
    paste_x = (canvas_size - char_w) // 2
    paste_y = canvas_size - foot_margin - char_h

    char_crop = img.crop(bbox)
    canvas.paste(char_crop, (paste_x, paste_y), char_crop)

    if not dry_run:
        canvas.save(path)

    tag = "DRYRUN" if dry_run else "OK    "
    return f"{tag}  {orig_w}x{orig_h} -> {canvas_size}x{canvas_size}  {path.name}"


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    default_art = script_dir.parent / "Art"

    parser = argparse.ArgumentParser(description="Normalize sprite canvases to a fixed size.")
    parser.add_argument("--dry-run", action="store_true", help="Preview only, no files written")
    parser.add_argument("--path",   default=str(default_art), help="Root folder to scan")
    parser.add_argument("--canvas", type=int, default=CANVAS_DEFAULT, help="Output canvas size (px)")
    parser.add_argument("--margin", type=int, default=MARGIN_DEFAULT,  help="Foot bottom margin (px)")
    args = parser.parse_args()

    root = Path(args.path)
    if not root.exists():
        print(f"ERROR: path not found: {root}")
        sys.exit(1)

    pngs = sorted(root.rglob("*.png"))
    print(f"Scanning {len(pngs)} PNGs in {root}")
    print(f"Canvas: {args.canvas}x{args.canvas} | foot margin: {args.margin}px")
    if args.dry_run:
        print("DRY RUN -- no files will be modified")
    print()

    ok = skip = warn = 0
    for p in pngs:
        result = normalize_sprite(p, args.canvas, args.margin, args.dry_run)
        print(result)
        if result.startswith("OK") or result.startswith("DRY"):
            ok += 1
        elif result.startswith("WARN"):
            warn += 1
        else:
            skip += 1

    verb = "would be " if args.dry_run else ""
    print(f"\n{ok} {verb}updated | {skip} skipped | {warn} warnings")


if __name__ == "__main__":
    main()

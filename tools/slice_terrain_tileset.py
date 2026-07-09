"""
slice_terrain_tileset.py

Slices a terrain source PNG into a tileset atlas.

Usage:
    python tools/slice_terrain_tileset.py

Outputs:
    Art/map/terrain/tiles/grass_tileset.png   — atlas spritesheet (10x5 grid of 64x64 tiles)
    Art/map/terrain/tiles/grass_tiles/        — individual tile PNGs (tile_00.png ... tile_49.png)
    Art/map/terrain/tiles/grass_solid.txt     — list of tile indices with >80% opaque pixels (safe to use)
"""

import os
from pathlib import Path
from PIL import Image

TILE_W = 64
TILE_H = 64
OPACITY_THRESHOLD = 0.80   # tile must be at least this fraction opaque to count as "solid"

SRC = Path("Art/map/terrain/640x320grassfull.png")
OUT_DIR = Path("Art/map/terrain/tiles")
TILES_DIR = OUT_DIR / "grass_tiles"
ATLAS_OUT = OUT_DIR / "grass_tileset.png"
SOLID_OUT = OUT_DIR / "grass_solid.txt"

def main():
    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    cols = w // TILE_W
    rows = h // TILE_H
    total = cols * rows

    print(f"Source: {w}x{h}px  ->  {cols}x{rows} grid  =  {total} tiles at {TILE_W}x{TILE_H}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TILES_DIR.mkdir(parents=True, exist_ok=True)

    # --- Slice tiles ---
    tiles = []
    solid_indices = []

    for row in range(rows):
        for col in range(cols):
            idx = row * cols + col
            x0, y0 = col * TILE_W, row * TILE_H
            tile = src.crop((x0, y0, x0 + TILE_W, y0 + TILE_H))

            # Measure opacity
            alpha_data = [p[3] for p in tile.getdata()]
            opaque_frac = sum(1 for a in alpha_data if a > 128) / len(alpha_data)

            tiles.append(tile)
            tile.save(TILES_DIR / f"tile_{idx:02d}.png")

            if opaque_frac >= OPACITY_THRESHOLD:
                solid_indices.append(idx)
                marker = "OK"
            else:
                marker = f"({opaque_frac:.0%})"

            print(f"  tile_{idx:02d}  r{row}c{col}  {marker}")

    # --- Write atlas ---
    atlas = Image.new("RGBA", (cols * TILE_W, rows * TILE_H), (0, 0, 0, 0))
    for idx, tile in enumerate(tiles):
        col = idx % cols
        row = idx // cols
        atlas.paste(tile, (col * TILE_W, row * TILE_H))
    atlas.save(ATLAS_OUT)
    print(f"\nAtlas saved: {ATLAS_OUT}")

    # --- Write solid list ---
    SOLID_OUT.write_text("\n".join(str(i) for i in solid_indices))
    print(f"Solid tiles ({len(solid_indices)}/{total}): {solid_indices}")
    print(f"Solid list saved: {SOLID_OUT}")


if __name__ == "__main__":
    # Run from project root
    os.chdir(Path(__file__).parent.parent)
    main()

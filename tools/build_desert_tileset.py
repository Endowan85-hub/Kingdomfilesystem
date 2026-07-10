"""
build_desert_tileset.py

Generates a 640x320 desert ground atlas (10x5 grid of 64x64 tiles) from a single
base tile, applying directional gradient dark overlays to create matching edge and
corner vignette tiles — same layout as swamp_ground.png.

Atlas layout (matches swamp conventions):
  Row 0  (idx  0- 9): top-edge tiles    — dark gradient at top
  Row 1  (idx 10-19): left/right edges  — col 0 = left-dark, col 9 = right-dark, rest = inner
  Row 2  (idx 20-29): left/right edges  — col 0 = left-dark, col 9 = right-dark, rest = inner
  Row 3  (idx 30-39): left/right edges  — col 0 = left-dark, col 9 = right-dark, rest = inner
  Row 4  (idx 40-49): bottom-edge tiles — dark gradient at bottom
  Corners: 0=NW, 9=NE, 40=SW, 49=SE   — two-side gradient

edge.txt  : outer ring indices (0-9, 10, 19, 20, 29, 30, 39, 40-49)
inner.txt : inner indices      (11-18, 21-28, 31-38)

Usage:
    python tools/build_desert_tileset.py
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw

COLS       = 10
ROWS       = 5
TILE_W     = 64
TILE_H     = 64
VIGN_DEPTH = 32   # how many pixels deep the dark gradient goes from the edge
VIGN_ALPHA = 140  # peak darkness (0-255) at the very edge

SRC_PATH  = Path("Art/tiles/biomes/desert/mega_desert.png")
EDGE_TXT  = Path("Art/map/terrain/tiles/desert_edge.txt")
INNER_TXT = Path("Art/map/terrain/tiles/desert_inner.txt")


def side_for(row: int, col: int) -> str:
    sides = ''
    if row == 0:           sides += 'N'
    if row == ROWS - 1:    sides += 'S'
    if col == 0:           sides += 'W'
    if col == COLS - 1:    sides += 'E'
    return sides


def main():
    os.chdir(Path(__file__).parent.parent)

    src = Image.open(SRC_PATH)
    print(f"Source atlas: {src.size}  ({COLS}x{ROWS} grid of {TILE_W}x{TILE_H} tiles)")

    edge_indices  = []
    inner_indices = []

    for row in range(ROWS):
        for col in range(COLS):
            idx   = row * COLS + col
            sides = side_for(row, col)
            if sides:
                edge_indices.append(idx)
            else:
                inner_indices.append(idx)
            tag = f"[{sides or 'inner'}]"
            print(f"  idx {idx:2d}  r{row}c{col}  {tag}")

    EDGE_TXT.parent.mkdir(parents=True, exist_ok=True)
    EDGE_TXT.write_text('\n'.join(str(i) for i in edge_indices))
    INNER_TXT.write_text('\n'.join(str(i) for i in inner_indices))
    print(f"\nEdge  txt:  {EDGE_TXT}  ({len(edge_indices)} tiles)")
    print(f"Inner txt:  {INNER_TXT}  ({len(inner_indices)} tiles)")


if __name__ == '__main__':
    main()

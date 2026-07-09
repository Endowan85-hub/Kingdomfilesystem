"""
build_grassdark_tileset.py

Takes Art/map/terrain/640x320grassdark.png (640x320, already a 10x5 grid of 64x64 tiles)
and produces:
  - Art/map/terrain/tiles/grassdark_tileset.png   (copy of source — it IS the tileset)
  - Art/map/terrain/tiles/grassdark_edge.txt      (outer-ring tiles with enough content)
  - Art/map/terrain/tiles/grassdark_inner.txt     (inner tiles with enough content)
  - Art/map/terrain/tiles/grassdark_solid.txt     (all content tiles — fallback)

Edge = row 0, row 4, col 0, or col 9 (outer ring of the 10x5 grid).
Inner = rows 1-3, cols 1-8.
A tile is "content" if >= MIN_ALPHA_FRACTION of its pixels are non-transparent.
"""

import shutil
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Install Pillow first:  pip install pillow")

import sys

_TERRAIN = Path(r"C:\Users\Patrick\dev\kingdom-(test)\Art\map\terrain")
TILES    = _TERRAIN / "tiles"

# Accept source filename as optional arg: python build_grassdark_tileset.py 640x320grassfulllight.png grasslight
if len(sys.argv) >= 3:
    SRC      = _TERRAIN / sys.argv[1]
    OUT_STEM = sys.argv[2]
else:
    SRC      = _TERRAIN / "640x320grassdark.png"
    OUT_STEM = "grassdark"

COLS = 10
ROWS = 5
TILE_W = 64
TILE_H = 64
MIN_ALPHA_FRACTION = 0.15   # tile must be at least 15% opaque to count

def is_edge(col, row):
    return row == 0 or row == ROWS - 1 or col == 0 or col == COLS - 1

def analyze(img):
    img = img.convert("RGBA")
    w, h = img.size
    assert w == COLS * TILE_W and h == ROWS * TILE_H, f"Expected {COLS*TILE_W}x{ROWS*TILE_H}, got {w}x{h}"

    pixels = img.load()
    threshold = int(TILE_W * TILE_H * MIN_ALPHA_FRACTION)

    edge_indices   = []
    inner_indices  = []
    solid_indices  = []

    print(f"\nAnalyzing {COLS}x{ROWS} grid of {TILE_W}x{TILE_H} tiles:")
    print(f"{'idx':>4}  {'pos':>8}  {'type':>6}  {'alpha%':>7}  keep")
    print("-" * 46)

    for row in range(ROWS):
        for col in range(COLS):
            idx = row * COLS + col
            x0, y0 = col * TILE_W, row * TILE_H

            opaque = sum(
                1 for py in range(y0, y0 + TILE_H)
                  for px in range(x0, x0 + TILE_W)
                  if pixels[px, py][3] > 30
            )

            frac = opaque / (TILE_W * TILE_H)
            keep = opaque >= threshold
            kind = "edge" if is_edge(col, row) else "inner"

            print(f"{idx:>4}  r{row}c{col:>2}  {kind:>6}  {frac*100:>6.1f}%  {'YES' if keep else 'no'}")

            if keep:
                solid_indices.append(idx)
                if kind == "edge":
                    edge_indices.append(idx)
                else:
                    inner_indices.append(idx)

    return edge_indices, inner_indices, solid_indices

def write_list(path, indices, label):
    path.write_text("\n".join(str(i) for i in indices) + "\n")
    print(f"\n{label}: {len(indices)} tiles -> {path.name}")
    print("  indices:", indices)

def remove_background(src_path):
    """Sample the top-left corner for the background color and make it transparent."""
    img = Image.open(src_path).convert("RGBA")
    pixels = img.load()
    # Sample background from top-left corner pixel
    bg = pixels[0, 0][:3]
    tolerance = 30

    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if (abs(r - bg[0]) <= tolerance and
                abs(g - bg[1]) <= tolerance and
                abs(b - bg[2]) <= tolerance):
                pixels[x, y] = (r, g, b, 0)
    print(f"Removed background color rgb{bg} (tolerance {tolerance})")
    return img


def main():
    TILES.mkdir(parents=True, exist_ok=True)

    img = remove_background(SRC)
    dst = TILES / f"{OUT_STEM}_tileset.png"
    img.save(dst)
    print(f"Saved tileset -> {dst}")

    edge, inner, solid = analyze(img)

    if not inner:
        print("\nWARNING: no inner tiles found -- using edge tiles as fallback for inner list")
        inner = edge[:]

    write_list(TILES / f"{OUT_STEM}_edge.txt",  edge,  "Edge tiles")
    write_list(TILES / f"{OUT_STEM}_inner.txt", inner, "Inner tiles")
    write_list(TILES / f"{OUT_STEM}_solid.txt", solid, "All solid tiles (fallback)")

if __name__ == "__main__":
    main()

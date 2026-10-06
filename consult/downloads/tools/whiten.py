"""Snap near-white pixels in the letterhead PNGs to pure white (Chromium and the
JPEG logo leave 253-254 values that can show as a faint box on a white page).
Keeps the 8-bit RGB, non-interlaced format the renderer requires.

    python3 consult/downloads/tools/whiten.py
"""
from pathlib import Path
from PIL import Image

assets = Path(__file__).resolve().parent.parent / "assets"
for name in ("header.png", "footer.png"):
    p = assets / name
    img = Image.open(p).convert("RGB")
    img = img.point(lambda v: 255 if v >= 246 else v)
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if min(r, g, b) >= 246:
                px[x, y] = (255, 255, 255)
    img.save(p, optimize=True)
    print("whitened", p.name, img.size)

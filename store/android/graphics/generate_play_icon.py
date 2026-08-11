"""Generate the Play Store app icon (512x512, 32-bit PNG with alpha).

Play requires the icon as "32-bit PNG (with alpha)" — `sips` drops the alpha
channel when it rescales, producing a 24-bit file that the console rejects.

Source is assets/icon/app_icon.png, the same file flutter_launcher_icons
consumes, so the store icon and the installed app icon cannot drift apart.
"""
from pathlib import Path

from PIL import Image

# This file lives at store/android/graphics/, so the repo root is three up.
REPO = Path(__file__).resolve().parents[3]
SRC = REPO / "assets/icon/app_icon.png"
OUT = REPO / "store/android/graphics/icon-512.png"

SIZE = 512

icon = Image.open(SRC).convert("RGBA")
icon = icon.resize((SIZE, SIZE), Image.LANCZOS)

OUT.parent.mkdir(parents=True, exist_ok=True)
icon.save(OUT, "PNG", optimize=True)

print(f"WROTE {OUT}")
print(f"SIZE {icon.size[0]}x{icon.size[1]} mode={icon.mode}")

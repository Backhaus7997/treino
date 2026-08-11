"""Compose the Play Store feature graphic (1024x500) from brand assets.

Colors come from lib/app/theme/app_palette.dart:
  ink   #0A0A0A   background
  mint  #2CE5A2   primary accent / wordmark
"""
from pathlib import Path

# This file lives at store/android/graphics/, so the repo root is three up.
REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "store/android/graphics/feature-graphic.png"

W, H = 1024, 500
INK = (10, 10, 10)
MINT = (44, 229, 162)

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("PIL_MISSING")

canvas = Image.new("RGB", (W, H), INK)
draw = ImageDraw.Draw(canvas)

# Subtle diagonal mint wash on the right third, so the panel does not read flat.
for x in range(int(W * 0.55), W):
    ratio = (x - W * 0.55) / (W * 0.45)
    shade = tuple(int(INK[i] + (MINT[i] - INK[i]) * ratio * 0.10) for i in range(3))
    draw.line([(x, 0), (x, H)], fill=shade)

# The source icon is a mint monogram on an opaque black tile. Pasting it whole
# leaves a visible black square on the panel, so key out the background and keep
# only the glyph.
icon = Image.open(REPO / "assets/icon/app_icon.png").convert("RGB")
glyph = Image.new("RGBA", icon.size, (0, 0, 0, 0))
src = icon.load()
dst = glyph.load()
for y in range(icon.size[1]):
    for x in range(icon.size[0]):
        r, g, b = src[x, y]
        # Mint is far brighter than the near-black tile; luminance separates them.
        if (r + g + b) > 120:
            dst[x, y] = (r, g, b, 255)

bbox = glyph.getbbox()
if bbox:
    glyph = glyph.crop(bbox)

glyph_h = 250
ratio = glyph_h / glyph.size[1]
glyph = glyph.resize((max(1, int(glyph.size[0] * ratio)), glyph_h), Image.LANCZOS)

icon_x = 110
icon_y = (H - glyph_h) // 2
canvas.paste(glyph, (icon_x, icon_y), glyph)
icon_size = glyph.size[0]


def load_font(size, bold=True):
    """Pick an upright grotesque. Explicit .ttf paths only — .ttc collections
    resolve to unpredictable faces (an italic slipped through that way)."""
    candidates = (
        [
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ]
        if bold
        else [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        ]
    )
    for path in candidates:
        if not Path(path).exists():
            continue
        try:
            font = ImageFont.truetype(path, size)
            if "Avenir" in path and bold:
                # Avenir Next collection: index 1 is Demi Bold, upright.
                font = ImageFont.truetype(path, size, index=1)
            return font
        except Exception:
            continue
    return ImageFont.load_default()


text_x = icon_x + icon_size + 70

wordmark_font = load_font(92)
tagline_font = load_font(34, bold=False)

# Measure so the block is actually centred rather than eyeballed.
wm_box = draw.textbbox((0, 0), "TREINO", font=wordmark_font)
wm_h = wm_box[3] - wm_box[1]
wm_y = 175

draw.text((text_x, wm_y), "TREINO", font=wordmark_font, fill=MINT, anchor="lt")

rule_y = wm_y + wm_h + 26
draw.rectangle([text_x, rule_y, text_x + 220, rule_y + 4], fill=MINT)

draw.text(
    (text_x, rule_y + 28),
    "Entrená. Medí. Progresá.",
    font=tagline_font,
    fill=(228, 228, 228),
    anchor="lt",
)

OUT.parent.mkdir(parents=True, exist_ok=True)
canvas.save(OUT, "PNG", optimize=True)
print(f"WROTE {OUT}")
print(f"SIZE {canvas.size[0]}x{canvas.size[1]} mode={canvas.mode}")

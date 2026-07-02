#!/usr/bin/env python3
"""
Storyteller icon — "Book that talks".
Shapes (back to front):
  1. Warm cream squircle background
  2. Teal book with darker spine and two light rules on the cover
  3. Coral speech bubble with a white waveform (the book speaking)
Flat and bold — reads at 16 px.
"""
from PIL import Image, ImageDraw
import os, subprocess

SIZE = 1024
S = SIZE / 150.0  # design was mocked at 150px; scale everything up


def px(v):
    return round(v * S)


def make_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    CREAM  = (242, 232, 213, 255)
    TEAL   = (42, 127, 119, 255)
    TEAL_D = (30, 95, 89, 255)
    RULE   = (191, 227, 223, 255)
    CORAL  = (226, 109, 92, 255)
    WHITE  = (255, 255, 255, 255)

    # ── Background squircle ──────────────────────────────────────────────────
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=px(34), fill=CREAM)

    # ── Book ─────────────────────────────────────────────────────────────────
    draw.rounded_rectangle([px(38), px(52), px(96), px(124)], radius=px(6), fill=TEAL)
    # Spine (left edge, darker)
    draw.rounded_rectangle([px(38), px(52), px(50), px(124)], radius=px(4), fill=TEAL_D)
    # Cover rules
    draw.rounded_rectangle([px(56), px(66), px(88), px(70)], radius=px(2), fill=RULE)
    draw.rounded_rectangle([px(56), px(76), px(80), px(80)], radius=px(2), fill=RULE)

    # ── Speech bubble ────────────────────────────────────────────────────────
    draw.rounded_rectangle([px(88), px(32), px(132), px(66)], radius=px(10), fill=CORAL)
    # Tail pointing down-left toward the book
    draw.polygon([(px(106), px(60)), (px(106), px(78)), (px(96), px(66))], fill=CORAL)

    # ── Waveform bars ────────────────────────────────────────────────────────
    for x, y, h in [(96, 44, 10), (103, 40, 18), (110, 44, 10), (117, 47, 5)]:
        draw.rounded_rectangle([px(x), px(y), px(x + 4), px(y + h)],
                               radius=px(2), fill=WHITE)

    return img


def main():
    iconset  = "/tmp/Storyteller.iconset"
    out_icns = "/Users/cameron/ScrivenerReader/AppIcon.icns"
    os.makedirs(iconset, exist_ok=True)

    print("Rendering icon…")
    base = make_icon()

    for sz in [16, 32, 128, 256, 512]:
        base.resize((sz,   sz  ), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}.png")
        base.resize((sz*2, sz*2), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}@2x.png")
        print(f"  {sz}x{sz} ✓")

    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_icns], check=True)
    print(f"\nCreated: {out_icns}")


if __name__ == "__main__":
    main()

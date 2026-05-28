#!/usr/bin/env python3
"""
Storyteller icon — minimal overhead reading view.
Shapes (back to front):
  1. Amber gradient background
  2. Flat open book (two pages + spine)
  3. Wide shoulders / upper body leaning over the book
  4. Bowed head (seen from above — mostly hair, forehead at bottom)
Clean and bold — reads at 16 px.
"""
from PIL import Image, ImageDraw, ImageFilter
import os, subprocess, math

SIZE = 1024

def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)

def make_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

    # ── Gradient background ──────────────────────────────────────────────────
    bg = Image.new('RGBA', (SIZE, SIZE))
    bd = ImageDraw.Draw(bg)
    for y in range(SIZE):
        bd.line([(0, y), (SIZE-1, y)],
                fill=lerp((234, 144, 22), (172, 58, 6), y / SIZE))
    mask = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE-1, SIZE-1], radius=185, fill=255)
    img.paste(bg, (0, 0), mask)
    draw = ImageDraw.Draw(img)

    SKIN  = (248, 226, 192)
    HAIR  = (72, 42, 12)
    PAGE  = (254, 250, 236)
    PAGE2 = (244, 240, 220)
    SP_C  = (178, 134, 68)
    EDGE  = (128, 72, 18)
    BORD  = (184, 156, 108)

    # ══════════════════════════════════════════════════════════════════════════
    #  1. BOOK  — flat open, gentle isometric perspective
    #     The far edge rises a little; the near edge is lower/closer.
    #     Drawn first so the person can rest in front of it.
    # ══════════════════════════════════════════════════════════════════════════
    FL  = (118, 480)
    FSP = (512, 454)
    FR  = (906, 480)
    NL  = ( 88, 880)
    NSP = (512, 908)
    NR  = (936, 880)

    draw.polygon([FL, FSP, NSP, NL],  fill=PAGE)
    draw.polygon([FSP, FR,  NR, NSP], fill=PAGE2)

    sw = 24
    draw.polygon([
        (FSP[0]-sw//2, FSP[1]), (FSP[0]+sw//2, FSP[1]),
        (NSP[0]+sw//2, NSP[1]), (NSP[0]-sw//2, NSP[1]),
    ], fill=SP_C)
    draw.polygon([FL, FSP, NSP, NL],  outline=BORD, width=4)
    draw.polygon([FSP, FR, NR, NSP],  outline=BORD, width=4)

    th = 38
    draw.polygon([NL, NSP, (NSP[0], NSP[1]+th), (NL[0], NL[1]+th)],  fill=EDGE)
    draw.polygon([NSP, NR,  (NR[0], NR[1]+th), (NSP[0], NSP[1]+th)], fill=EDGE)

    # ══════════════════════════════════════════════════════════════════════════
    #  2. SHOULDERS / UPPER BODY
    #     A wide stadium shape overlapping the book's far edge — the person
    #     is leaning forward over the book.  Drawn on top of the book.
    # ══════════════════════════════════════════════════════════════════════════
    SX, SY   = 512, 422        # centre of shoulder bar — raised so book pages show
    SW, SH   = 268, 72         # half-width, half-height
    # Stadium: rounded-rectangle (pill shape)
    draw.rounded_rectangle([SX-SW, SY-SH, SX+SW, SY+SH], radius=SH, fill=SKIN)

    # Short neck stub connecting shoulders to head
    draw.rounded_rectangle([SX-28, SY-SH-20, SX+28, SY-SH+30], radius=14, fill=SKIN)

    # ══════════════════════════════════════════════════════════════════════════
    #  3. HEAD  — bowed toward the book; seen from slightly above/behind.
    #     Oval (wider than tall = foreshortened from above).
    #     Hair covers the upper ⅔; a forehead sliver at the bottom hints
    #     at the face angled downward toward the pages.
    # ══════════════════════════════════════════════════════════════════════════
    HX, HY   = 512, 262
    HRX, HRY = 130, 116

    # Soft drop-shadow under head for depth
    shad = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shad).ellipse(
        [HX-HRX+10, HY-HRY+20, HX+HRX+10, HY+HRY+30], fill=(0, 0, 0, 60))
    img.alpha_composite(shad.filter(ImageFilter.GaussianBlur(22)))
    draw = ImageDraw.Draw(img)

    # Skin base
    draw.ellipse([HX-HRX, HY-HRY, HX+HRX, HY+HRY], fill=SKIN)

    # Hair cap: polygon tracing the ellipse from ~200° → ~340° (back + top),
    # then cutting straight across just above the forehead.
    hair_pts = []
    for deg in range(200, 342):
        rad = math.radians(deg)
        hair_pts.append((HX + HRX * math.cos(rad),
                         HY + HRY * math.sin(rad)))
    # Close the polygon across the forehead at about 85 % down the oval
    hair_pts.append((HX + 90,  HY + HRY * 0.62))
    hair_pts.append((HX - 90,  HY + HRY * 0.62))
    draw.polygon(hair_pts, fill=HAIR)

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

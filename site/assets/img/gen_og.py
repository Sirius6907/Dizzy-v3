"""Regenerates the social card (site/assets/img/og.jpg) from a real app shot.

Run after a screenshot refresh:  python site/assets/img/gen_og.py
Needs Pillow. Uses Windows system fonts when present, PIL's default otherwise.
Brand: Prism dark — base #070910, red #F4363F, violet #8B5CF6.
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SHOT = os.path.join(HERE, "shots", "home.webp")
OUT = os.path.join(HERE, "og.jpg")
W, H = 1200, 630

BASE = (7, 9, 16)
RED = (244, 54, 63)
VIOLET = (139, 92, 246)
TEXT = (243, 245, 250)
MUTED = (160, 168, 188)


def font(names, size):
    for name in names:
        for root in (r"C:\Windows\Fonts", "/usr/share/fonts/truetype/dejavu", "/System/Library/Fonts"):
            path = os.path.join(root, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
    return ImageFont.load_default() if size < 40 else ImageFont.load_default()


def bold(size):
    return font(["segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"], size)


def regular(size):
    return font(["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"], size)


img = Image.new("RGB", (W, H), BASE)
d = ImageDraw.Draw(img, "RGBA")

# two soft glows: red top-right, violet bottom-left
for cx, cy, r, c in ((1010, 40, 620, RED), (60, 600, 520, VIOLET)):
    for rr in range(r, 0, -8):
        alpha = int(46 * (1 - rr / r) ** 2.2)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=c + (alpha,))

# the real home screen, inside a phone frame
shot = Image.open(SHOT).convert("RGB")
ph = 552
pw = round(shot.width * ph / shot.height)
shot = shot.resize((pw, ph), Image.LANCZOS)
px, py = W - pw - 84, (H - ph) // 2
d.rounded_rectangle([px - 11, py - 11, px + pw + 11, py + ph + 11], 40,
                    fill=(24, 31, 45), outline=(255, 255, 255, 60), width=2)
mask = Image.new("L", (pw, ph), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw, ph], 30, fill=255)
img.paste(shot, (px, py), mask)

# copy block
d.text((72, 74), "Dizzy", font=bold(40), fill=(255, 255, 255))
y = 196
for text, color in (("One app for", (255, 255, 255)),
                    ("everything you watch,", (255, 255, 255)),
                    ("listen and read.", RED)):
    d.text((72, y), text, font=bold(62), fill=color)
    y += 74

d.text((72, 438), "Movies · Series · Music · Manga · Audiobooks · Live TV", font=regular(25), fill=MUTED)
d.text((72, 478), "Watch parties, friends and DMs built in.", font=regular(25), fill=MUTED)

d.line([72, 545, 800, 545], fill=(255, 255, 255, 40), width=1)
d.text((72, 562), "Android · Windows · Linux  —  free & open source", font=bold(23), fill=(255, 95, 104))

img.save(OUT, "JPEG", quality=92, optimize=True, progressive=True)
print("wrote", OUT, img.size, os.path.getsize(OUT) // 1024, "KB")

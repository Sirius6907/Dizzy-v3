"""Phase Q: generate landing screenshots (PIL only, zero network).
Hero phone mocks: CSS-free gradient phone frames rendered as WebP, used
inside the CSS phone mockups as screen art. og.png: social card 1200x630.
Style: Midnight Signal — base #07070B, gradient #7C5CFF -> #39D0FF."""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.join(os.path.dirname(__file__), "img")
os.makedirs(OUT, exist_ok=True)

BASE = (7, 7, 11)
VIOLET = (124, 92, 255)
CYAN = (57, 208, 255)
PINK = (255, 77, 109)
TEXT = (244, 245, 250)
MUTED = (138, 143, 163)

try:
    FONT_B = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 44)
    FONT_M = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 26)
    FONT_S = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
except Exception:
    FONT_B = FONT_M = FONT_S = ImageFont.load_default()


def grad_bg(w, h, c1=VIOLET, c2=CYAN, dark=True):
    img = Image.new("RGB", (w, h), BASE if dark else "#101018")
    d = ImageDraw.Draw(img, "RGBA")
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)],
               fill=tuple(int(c1[i] * 0.16 * (1 - t) + c2[i] * 0.16 * t + 7) for i in range(3)))
    # glow orbs
    for (ox, oy, r, c) in ((w * .8, h * .15, w * .55, VIOLET), (w * .1, h * .85, w * .5, CYAN)):
        r = int(r); ox = int(ox); oy = int(oy)
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        g = ImageDraw.Draw(glow)
        for rr in range(r, 0, -6):
            a = int(46 * (1 - rr / r) ** 2)
            g.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=c + (a,))
        img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    return img


def screen_home(w=540, h=1140, title="Dizzy", rows=("Continue watching", "Trending movies", "Your music")):
    img = grad_bg(w, h)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([28, 60, w - 28, 150], 26, fill=(19, 21, 32))
    d.text((52, 84), title, font=FONT_B, fill=TEXT)
    d.text((52, 122), "Your media.   Your rules.", font=FONT_S, fill=MUTED)
    y = 180
    for i, r in enumerate(rows):
        d.rounded_rectangle([28, y, w - 28, y + 190], 26, fill=(16, 18, 27))
        # poster strip: gradient tiles
        for j in range(3):
            x0 = 44 + j * 158
            hue = VIOLET if (i + j) % 2 == 0 else CYAN
            d.rounded_rectangle([x0, y + 16, x0 + 142, y + 130], 16,
                                fill=tuple(int(v * 0.35) + 10 for v in hue))
            d.rounded_rectangle([x0, y + 138, x0 + 142, y + 150], 6, fill=(40, 43, 60))
        d.text((52, y + 158), r, font=FONT_M, fill=TEXT)
        y += 210
    # bottom nav
    d.rounded_rectangle([28, h - 120, w - 28, h - 44], 30, fill=(19, 21, 32))
    for j, ico in enumerate(("H", "S", "D", "P")):
        d.text((76 + j * 122, h - 104), ico, font=FONT_B,
               fill=CYAN if j == 0 else MUTED)
    return img


def screen_player(w=540, h=1140):
    img = grad_bg(w, h, PINK, VIOLET)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([28, 60, w - 28, 560], 26, fill=(10, 10, 16))
    d.polygon([(w // 2 - 34, 220), (w // 2 - 34, 340), (w // 2 + 52, 280)], fill=TEXT)
    d.text((52, 580), "Watch Together", font=FONT_B, fill=TEXT)
    d.text((52, 626), "3 friends watching in sync", font=FONT_M, fill=MUTED)
    # avatars row
    for j in range(3):
        x = 52 + j * 76
        d.ellipse([x, 680, x + 60, 740], fill=VIOLET if j % 2 == 0 else CYAN)
    # seek bar
    d.rounded_rectangle([52, 790, w - 52, 802], 6, fill=(40, 43, 60))
    d.rounded_rectangle([52, 790, w // 2 + 60, 802], 6, fill=CYAN)
    d.text((52, 830), "Voice room live", font=FONT_M, fill=PINK)
    d.rounded_rectangle([28, h - 200, w - 28, h - 60], 26, fill=(19, 21, 32))
    d.text((52, h - 176), "Chat", font=FONT_M, fill=TEXT)
    d.text((52, h - 140), "This scene gave me chills", font=FONT_S, fill=MUTED)
    return img


def save(img, name, max_w=720, q=80):
    if img.width > max_w:
        img = img.resize((max_w, int(img.height * max_w / img.width)), Image.LANCZOS)
    p = os.path.join(OUT, name)
    img.save(p, "WEBP", quality=q, method=6)
    print(name, img.size, os.path.getsize(p) // 102, "KB")


save(screen_home(), "screen-home.webp")
save(screen_player(), "screen-player.webp")

# og card 1200x630
og = grad_bg(1200, 630)
d = ImageDraw.Draw(og)
f1 = FONT_B.font_variant(size=120) if hasattr(FONT_B, "font_variant") else FONT_B
f2 = FONT_M.font_variant(size=40) if hasattr(FONT_M, "font_variant") else FONT_M
d.text((80, 190), "Dizzy", font=f1, fill=TEXT)
d.text((80, 330), "Your media. Your rules.", font=f2, fill=MUTED)
d.text((80, 400), "Android  •  Windows  •  Linux   —   free & open", font=f2, fill=CYAN)
og.save(os.path.join(OUT, "og.png"))
print("og.png", og.size, os.path.getsize(os.path.join(OUT, "og.png")) // 1024, "KB")

# favicon: rounded square with play glyph
fav = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
d = ImageDraw.Draw(fav)
d.rounded_rectangle([4, 4, 124, 124], 30, fill=VIOLET)
d.polygon([(48, 34), (48, 94), (92, 64)], fill=(255, 255, 255))
fav.save(os.path.join(OUT, "favicon.png"))
fav.resize((32, 32), Image.LANCZOS).save(os.path.join(OUT, "favicon-32.png"))
print("favicon ok")

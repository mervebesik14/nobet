"""Baykuş uygulama simgesi: lacivert gece zemini, yıldızlar, iri gözlü
baykuş; göğsünde küçük sağlık artısı. 4 kat büyük çizilip 1024'e
küçültülür.

Kullanım: python3 assets/icon/make_icon.py assets/icon
ardından: dart run flutter_launcher_icons
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4  # süper örnekleme
N = 1024 * S
OUT = sys.argv[1] if len(sys.argv) > 1 else "."

NIGHT_TOP = (36, 58, 120)
NIGHT_BOTTOM = (11, 20, 52)
BODY = (58, 92, 170)
BODY_DARK = (44, 72, 140)
FACE = (240, 232, 214)
IRIS = (255, 200, 69)
PUPIL = (12, 22, 54)
BEAK = (242, 150, 52)
STAR = (255, 214, 110)
WHITE = (255, 255, 255)


def s(v):
    return int(round(v * S))


def gradient(size, c1, c2):
    """Yukarıdan aşağı geçiş (gece göğü)."""
    w, h = size
    small = Image.new("RGB", (1, 256))
    px = small.load()
    for y in range(256):
        t = y / 255
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return small.resize((w, h), Image.BICUBIC)


def star(d, cx, cy, big, small):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        r = big if i % 2 == 0 else small
        pts.append((s(cx + r * math.cos(ang)), s(cy + r * math.sin(ang))))
    d.polygon(pts, fill=STAR)


def background():
    bg = gradient((N, N), NIGHT_TOP, NIGHT_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([s(212), s(180), s(812), s(780)], fill=(120, 160, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(s(120)))
    bg = Image.alpha_composite(bg, glow)
    d = ImageDraw.Draw(bg)
    star(d, 160, 170, 30, 9)
    star(d, 868, 210, 22, 7)
    star(d, 120, 420, 14, 5)
    star(d, 900, 470, 16, 5)
    return bg


def owl():
    """Baykuş, saydam katman (1024 koordinatlarında)."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # Gölge.
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [s(250), s(300), s(774), s(900)], fill=(0, 0, 20, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(40)))
    layer = Image.alpha_composite(layer, shadow)
    d = ImageDraw.Draw(layer)

    # Kulak tüyleri ve gövde.
    d.polygon([(s(262), s(400)), (s(286), s(168)), (s(440), s(300))], fill=BODY)
    d.polygon([(s(762), s(400)), (s(738), s(168)), (s(584), s(300))], fill=BODY)
    d.ellipse([s(236), s(250), s(788), s(880)], fill=BODY)

    # Göğüs tüyleri (hafif koyu kavisler).
    for row, y in enumerate((690, 752, 814)):
        xs = (420, 512, 604) if row % 2 == 0 else (466, 558)
        for x in xs:
            d.arc(
                [s(x - 34), s(y - 26), s(x + 34), s(y + 26)],
                start=20,
                end=160,
                fill=BODY_DARK,
                width=s(12),
            )

    # Yüz diski: iki örtüşen daire.
    for cx in (398, 626):
        d.ellipse([s(cx - 150), s(326), s(cx + 150), s(626)], fill=FACE)

    # Gözler: altın iris, lacivert göz bebeği, beyaz parıltı.
    for cx in (398, 626):
        cy = 476
        d.ellipse([s(cx - 108), s(cy - 108), s(cx + 108), s(cy + 108)], fill=IRIS)
        d.ellipse([s(cx - 62), s(cy - 62), s(cx + 62), s(cy + 62)], fill=PUPIL)
        d.ellipse([s(cx - 38), s(cy - 44), s(cx - 6), s(cy - 12)], fill=WHITE)

    # Gaga.
    d.polygon([(s(478), s(590)), (s(546), s(590)), (s(512), s(662))], fill=BEAK)

    # Göğüste sağlık artısı.
    cx, cy, arm, th = 512, 790, 44, 26
    d.rounded_rectangle(
        [s(cx - th / 2), s(cy - arm), s(cx + th / 2), s(cy + arm)],
        radius=s(8),
        fill=WHITE,
    )
    d.rounded_rectangle(
        [s(cx - arm), s(cy - th / 2), s(cx + arm), s(cy + th / 2)],
        radius=s(8),
        fill=WHITE,
    )
    return layer


def main():
    bg = background()
    em = owl()
    full = Image.alpha_composite(bg, em).resize((1024, 1024), Image.LANCZOS)
    full.convert("RGB").save(f"{OUT}/icon.png")

    # Android uyarlanabilir simge: zemin ve ön plan ayrı. Ön plan güvenli
    # alana (orta ~%66) sığsın diye küçültülüp ortalanır.
    bg.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(
        f"{OUT}/icon_background.png"
    )
    scale = 0.68
    small = em.resize((round(N * scale), round(N * scale)), Image.LANCZOS)
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    off = (N - small.width) // 2
    # Baykuşun merkezi (512, 540) tuval merkezine gelsin.
    fg.paste(small, (off, off - round(28 * S * scale)), small)
    fg.resize((1024, 1024), Image.LANCZOS).save(f"{OUT}/icon_foreground.png")


main()

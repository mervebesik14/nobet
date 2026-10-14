"""Nöbetçi uygulama simgesi: geçişli zemin, takvim kartı, sağlık artısı,
gece nöbeti hilali. 4 kat büyük çizilip 1024'e küçültülür."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # süper örnekleme
N = 1024 * S
OUT = sys.argv[1] if len(sys.argv) > 1 else "."

TEAL = (18, 163, 143)
NAVY = (29, 63, 122)
HEADER = (13, 128, 113)
CROSS = (18, 163, 143)
BADGE = (29, 63, 122)
MOON = (255, 200, 69)
WHITE = (255, 255, 255)


def s(v):
    return int(round(v * S))


def gradient(size, c1, c2):
    """Sol üstten sağ alta çapraz geçiş."""
    w, h = size
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return small.resize((w, h), Image.BICUBIC)


def background():
    bg = gradient((N, N), TEAL, NAVY).convert("RGBA")
    # Sol üstte hafif ışık.
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse([s(-300), s(-300), s(600), s(600)], fill=(255, 255, 255, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(s(140)))
    return Image.alpha_composite(bg, glow)


def emblem():
    """Kart + rozet, saydam katman (1024 koordinatlarında tasarlandı)."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # Gölge.
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [s(232), s(292), s(792), s(852)], radius=s(110), fill=(5, 20, 45, 110)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(34)))
    layer = Image.alpha_composite(layer, shadow)

    d = ImageDraw.Draw(layer)
    # Kart gövdesi.
    d.rounded_rectangle(
        [s(232), s(262), s(792), s(822)], radius=s(110), fill=WHITE
    )
    # Başlık bandı (üst köşeler yuvarlak).
    band = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.rounded_rectangle(
        [s(232), s(262), s(792), s(822)], radius=s(110), fill=HEADER
    )
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rectangle([0, 0, N, s(402)], fill=255)
    band.putalpha(_and(band.split()[3], mask))
    layer = Image.alpha_composite(layer, band)
    d = ImageDraw.Draw(layer)

    # Halkalar.
    for cx in (392, 632):
        d.rounded_rectangle(
            [s(cx - 26), s(212), s(cx + 26), s(330)],
            radius=s(26),
            fill=WHITE,
        )
        d.rounded_rectangle(
            [s(cx - 14), s(232), s(cx + 14), s(310)],
            radius=s(14),
            fill=(220, 236, 240),
        )

    # Sağlık artısı.
    cx, cy, arm, th = 512, 612, 118, 78
    r = s(22)
    d.rounded_rectangle(
        [s(cx - th / 2), s(cy - arm), s(cx + th / 2), s(cy + arm)],
        radius=r,
        fill=CROSS,
    )
    d.rounded_rectangle(
        [s(cx - arm), s(cy - th / 2), s(cx + arm), s(cy + th / 2)],
        radius=r,
        fill=CROSS,
    )

    # Gece nöbeti rozeti: lacivert daire, beyaz kenar, sarı hilal + yıldız.
    bx, by, br = 770, 300, 118
    d.ellipse([s(bx - br), s(by - br), s(bx + br), s(by + br)], fill=WHITE)
    br2 = br - 18
    d.ellipse([s(bx - br2), s(by - br2), s(bx + br2), s(by + br2)], fill=BADGE)
    mr = 58
    mx, my = bx - 8, by + 4
    d.ellipse([s(mx - mr), s(my - mr), s(mx + mr), s(my + mr)], fill=MOON)
    ox, oy = mx + 30, my - 22
    d.ellipse([s(ox - mr), s(oy - mr), s(ox + mr), s(oy + mr)], fill=BADGE)
    # Küçük yıldız (dört köşeli parıltı).
    sx, sy, R, rr = bx + 44, by - 40, 22, 7
    pts = []
    import math
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = R if i % 2 == 0 else rr
        pts.append((s(sx + rad * math.cos(ang)), s(sy + rad * math.sin(ang))))
    d.polygon(pts, fill=MOON)
    return layer


def _and(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a, b)


def main():
    bg = background()
    em = emblem()
    # Rozet sağa ağırlık verdiği için bütün biraz sola ve aşağı kayar.
    shifted = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shifted.paste(em, (s(-30), s(14)), em)
    em = shifted
    full = Image.alpha_composite(bg, em).resize((1024, 1024), Image.LANCZOS)
    full.convert("RGB").save(f"{OUT}/icon.png")

    # Android uyarlanabilir simge: zemin ve ön plan ayrı. Ön plan güvenli
    # alana (orta ~%66) sığsın diye küçültülüp ortalanır.
    bg.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(
        f"{OUT}/icon_background.png"
    )
    scale = 0.70
    small = em.resize((round(N * scale), round(N * scale)), Image.LANCZOS)
    fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    off = (N - small.width) // 2
    # Kart merkezi (512, 542) tuval merkezine gelsin.
    fg.paste(small, (off, off - round(30 * S * scale)), small)
    fg.resize((1024, 1024), Image.LANCZOS).save(f"{OUT}/icon_foreground.png")


main()

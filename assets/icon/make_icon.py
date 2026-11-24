"""Sabaha Kadar uygulama simgesi: lacivert gece göğü, hilal ve yıldızlar,
ufuktan doğan güneş ve ufuk boyunca uzanan beyaz kalp ritmi (EKG) çizgisi:
geceden sabaha süren 24 saatlik nöbet. 4 kat büyük çizilip 1024'e
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

SKY_TOP = (10, 18, 52)
SKY_LOW = (38, 58, 128)
GROUND = (9, 15, 42)
SUN_IN = (255, 214, 102)
SUN_OUT = (255, 138, 76)
MOON = (255, 232, 170)
STAR = (255, 224, 150)
WHITE = (255, 255, 255)

HORIZON = 610


def s(v):
    return int(round(v * S))


def vgradient(size, c1, c2):
    w, h = size
    col = Image.new("RGB", (1, 256))
    px = col.load()
    for y in range(256):
        t = y / 255
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return col.resize((w, h), Image.BICUBIC)


def star(d, cx, cy, big, small):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        r = big if i % 2 == 0 else small
        pts.append((s(cx + r * math.cos(ang)), s(cy + r * math.sin(ang))))
    d.polygon(pts, fill=STAR)


def background():
    """Gece göğü, ufuk ışığı, hilal, yıldızlar ve koyu zemin."""
    img = vgradient((N, N), SKY_TOP, SKY_LOW).convert("RGBA")

    # Ufukta sabah ışığı (turuncu-pembe hale).
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        [s(112), s(HORIZON - 300), s(912), s(HORIZON + 300)],
        fill=(255, 140, 90, 150),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(s(110)))
    img = Image.alpha_composite(img, glow)

    # Hilal: dolu daireden kaydırılmış daire maskeyle çıkarılır.
    mx, my, mr = 250, 238, 92
    ox, oy = mx + 42, my - 30
    mask = Image.new("L", (N, N), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([s(mx - mr), s(my - mr), s(mx + mr), s(my + mr)], fill=255)
    md.ellipse([s(ox - mr), s(oy - mr), s(ox + mr), s(oy + mr)], fill=0)
    moon = Image.new("RGBA", (N, N), MOON + (255,))
    img.paste(moon, (0, 0), mask)
    d = ImageDraw.Draw(img)
    star(d, 470, 150, 26, 8)
    star(d, 790, 230, 34, 10)
    star(d, 640, 330, 14, 5)
    star(d, 150, 430, 16, 5)
    star(d, 900, 420, 14, 5)
    return img


def sun_and_ground():
    """Doğan güneş (ufkun üstündeki yarım daire) ve koyu zemin."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    r = 225
    sun = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    grad = vgradient((s(2 * r), s(2 * r)), SUN_IN, SUN_OUT).convert("RGBA")
    mask = Image.new("L", grad.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, grad.width - 1, grad.height - 1], fill=255)
    sun.paste(grad, (s(512 - r), s(HORIZON - r)), mask)
    layer = Image.alpha_composite(layer, sun)
    d = ImageDraw.Draw(layer)
    # Zemin ufkun altını örter; güneş yarısıyla doğuyor görünür.
    d.rectangle([0, s(HORIZON), N, N], fill=GROUND)
    # Zeminde hafif ışık yansıması.
    refl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(refl).ellipse(
        [s(272), s(HORIZON + 10), s(752), s(HORIZON + 90)],
        fill=(255, 150, 90, 70),
    )
    refl = refl.filter(ImageFilter.GaussianBlur(s(26)))
    return Image.alpha_composite(layer, refl)


def ecg():
    """Ufuk boyunca kalp ritmi çizgisi; ortada belirgin atım."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    y = HORIZON
    pts = [
        (60, y),
        (330, y),
        (370, y - 46),
        (410, y),
        (450, y),
        (500, y - 250),
        (560, y + 150),
        (604, y),
        (650, y),
        (690, y - 60),
        (730, y),
        (964, y),
    ]
    width = 40
    # Hafif parıltı.
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(
        [(s(x), s(v)) for x, v in pts], fill=(255, 255, 255, 120),
        width=s(width + 34), joint="curve",
    )
    glow = glow.filter(ImageFilter.GaussianBlur(s(18)))
    layer = Image.alpha_composite(layer, glow)
    d = ImageDraw.Draw(layer)
    d.line([(s(x), s(v)) for x, v in pts], fill=WHITE, width=s(width),
           joint="curve")
    # Uçlar yuvarlak.
    for x, v in (pts[0], pts[-1]):
        rr = width / 2
        d.ellipse([s(x - rr), s(v - rr), s(x + rr), s(v + rr)], fill=WHITE)
    return layer


def main():
    bg = background()
    fg = Image.alpha_composite(sun_and_ground(), ecg())
    full = Image.alpha_composite(bg, fg).resize((1024, 1024), Image.LANCZOS)
    full.convert("RGB").save(f"{OUT}/icon.png")

    # Android uyarlanabilir simge: zemin (gök) ve ön plan (güneş, zemin,
    # EKG). Ön plan güvenli alana sığsın diye küçültülüp ortalanır; zemin
    # şeridi tam genişlikte kalsın diye ön planın alt kısmı da genişletilir.
    bg.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(
        f"{OUT}/icon_background.png"
    )
    scale = 0.72
    small = fg.resize((round(N * scale), round(N * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    off = (N - small.width) // 2
    shift = round((HORIZON - 512) * S * scale)
    top = off - shift
    ImageDraw.Draw(out).rectangle([0, top + small.height // 2 + shift, N, N],
                                  fill=GROUND)
    out.paste(small, (off, top), small)
    out.resize((1024, 1024), Image.LANCZOS).save(f"{OUT}/icon_foreground.png")


main()

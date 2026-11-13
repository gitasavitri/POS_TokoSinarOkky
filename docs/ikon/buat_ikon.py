"""Pembuat ikon (jalankan: python3 docs/ikon/buat_ikon.py app_toko/assets/fonts/PlusJakartaSans_800ExtraBold.ttf <folder>).
Buat ikon aplikasi sederhana 'SO' (Sinar Okky): .ico multi-ukuran untuk Windows + PNG untuk layar masuk."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = sys.argv[1]
OUT = sys.argv[2]  # folder tujuan
S = 1024

def ikon(warna_atas, warna_bawah, label=None):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # latar gradasi dalam kotak sudut bulat
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(warna_atas[i] * (1 - t) + warna_bawah[i] * t) for i in range(3)) + (255,)
        gd.line([(0, y), (S, y)], fill=c)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=210, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # sinar matahari kecil di kanan atas
    cx, cy, r = 760, 250, 70
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 196, 61, 255))
    import math
    for k in range(8):
        a = k * math.pi / 4
        x1, y1 = cx + math.cos(a) * (r + 30), cy + math.sin(a) * (r + 30)
        x2, y2 = cx + math.cos(a) * (r + 80), cy + math.sin(a) * (r + 80)
        d.line([(x1, y1), (x2, y2)], fill=(255, 196, 61, 255), width=34)
    f = ImageFont.truetype(FONT, 470)
    teks = "SO"
    bb = d.textbbox((0, 0), teks, font=f)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    y0 = (S - h) // 2 - bb[1] + (60 if label else 90)
    d.text(((S - w) // 2 - bb[0], y0), teks, font=f, fill=(255, 255, 255, 255))
    if label:
        f2 = ImageFont.truetype(FONT, 150)
        bb = d.textbbox((0, 0), label, font=f2)
        w = bb[2] - bb[0]
        d.rounded_rectangle([(S - w) // 2 - 50, 790, (S + w) // 2 + 50, 960], radius=60, fill=(255, 196, 61, 255))
        d.text(((S - w) // 2 - bb[0], 875 - (bb[3] + bb[1]) // 2), label, font=f2, fill=(16, 42, 92, 255))
    return img

toko = ikon((30, 136, 229), (13, 71, 161))
pusat = ikon((26, 46, 92), (10, 22, 52), label="PUSAT")
ukuran = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
for nama, im in (("toko", toko), ("pusat", pusat)):
    im.save(f"{OUT}/ikon_{nama}.ico", sizes=ukuran)
    im.resize((512, 512), Image.LANCZOS).save(f"{OUT}/ikon_{nama}.png")
    im.resize((180, 180), Image.LANCZOS).save(f"{OUT}/ikon_{nama}_kecil.png")
print("ok")

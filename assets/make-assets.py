#!/usr/bin/env python3
"""Generates every IBA KeyMorph image from the IBA panda artwork (assets/panda-source.png).

    python3 assets/make-assets.py

PANDA_FOCUS is the centre of the panda's face in the source picture (fractions of width/height);
change it when replacing the artwork. Requires Pillow and the DejaVu Sans Bold font.
"""
import io
import os
import struct

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "panda-source.png")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

PANDA_FOCUS = (0.578, 0.36)  # face centre in panda-source.png
SQUARE_SIDE = 0.85  # square crop side as a fraction of the picture height
CLOSE_UP_SIDE = 0.5  # crop for tiny icons: mostly the face

GLOW = (46, 204, 113)
DARK = (11, 21, 18)
WHITE = (255, 255, 255)


def source():
    return Image.open(SOURCE).convert("RGB")


def crop_around(img, cx, cy, w, h):
    left = min(max(0, int(cx - w / 2)), img.width - int(w))
    top = min(max(0, int(cy - h / 2)), img.height - int(h))
    return img.crop((left, top, left + int(w), top + int(h)))


def panda_square(s, close_up=False):
    img = source()
    side = img.height * (CLOSE_UP_SIDE if close_up else SQUARE_SIDE)
    cx, cy = img.width * PANDA_FOCUS[0], img.height * PANDA_FOCUS[1]
    if not close_up:
        cy += side * 0.12  # leave room for the badge under the face
    out = crop_around(img, cx, cy, side, side).resize((s, s), Image.LANCZOS)
    if s > side:
        out = out.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    return out.convert("RGBA")


def swap_badge(img, s):
    """'A ⇄ Я' badge across the bottom of the picture."""
    d = ImageDraw.Draw(img)
    h = int(s * 0.25)
    top = s - h - int(s * 0.03)
    pad = int(s * 0.08)
    d.rounded_rectangle([pad, top, s - pad, top + h], radius=h // 2, fill=DARK + (225,), outline=GLOW + (255,), width=max(1, s // 96))
    font = ImageFont.truetype(FONT, int(h * 0.72))
    cy = top + h / 2
    for text, cx in (("A", s * 0.3), ("Я", s * 0.7)):
        box = d.textbbox((0, 0), text, font=font)
        d.text((cx - (box[2] - box[0]) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=font, fill=WHITE)
    lw = max(1, int(h * 0.09))
    x0, x1, a = s * 0.41, s * 0.59, h * 0.14
    for y, direction in ((cy - h * 0.12, 1), (cy + h * 0.12, -1)):
        d.line([(x0, y), (x1, y)], fill=GLOW + (255,), width=lw)
        tip = x1 if direction == 1 else x0
        d.polygon([(tip + direction * a * 0.4, y), (tip - direction * a, y - a), (tip - direction * a, y + a)], fill=GLOW + (255,))


def rounded(img, radius_ratio=0.22):
    s = img.width
    mask = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1], radius=int(s * 4 * radius_ratio), fill=255)
    mask = mask.resize((s, s), Image.LANCZOS)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def app_icon(s, badge=True):
    img = panda_square(s, close_up=s <= 32)
    if badge:
        swap_badge(img, s)
    return rounded(img)


def wizard_banner(w, h):
    """Tall installer banner: the panda in full height with the product name below."""
    img = source()
    strip_h = img.height
    strip_w = strip_h * w / h
    banner = crop_around(img, img.width * PANDA_FOCUS[0], strip_h / 2, strip_w, strip_h)
    banner = banner.resize((w * 2, h * 2), Image.LANCZOS).convert("RGBA")
    shade = Image.new("RGBA", banner.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shade)
    for y in range(banner.height):
        t = max(0.0, (y / banner.height - 0.5) / 0.5)
        d.line([(0, y), (banner.width, y)], fill=DARK + (int(235 * t),))
    banner = Image.alpha_composite(banner, shade)
    d = ImageDraw.Draw(banner)
    for text, size, y, color in (("IBA KeyMorph", 0.105, 0.78, WHITE), ("EN ⇄ RU", 0.075, 0.86, GLOW)):
        font = ImageFont.truetype(FONT, int(banner.width * size))
        box = d.textbbox((0, 0), text, font=font)
        d.text(((banner.width - (box[2] - box[0])) / 2 - box[0], banner.height * y), text, font=font, fill=color)
    return banner.resize((w, h), Image.LANCZOS)


def write_ico(frames, path):
    """ICO with PNG-compressed frames (supported since Windows Vista)."""
    entries, blobs = [], []
    offset = 6 + 16 * len(frames)
    for frame in frames:
        buf = io.BytesIO()
        frame.save(buf, format="PNG")
        data = buf.getvalue()
        n = frame.width
        entries.append(struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(data), offset))
        blobs.append(data)
        offset += len(data)
    with open(path, "wb") as f:
        f.write(struct.pack("<HHH", 0, 1, len(frames)))
        f.write(b"".join(entries))
        f.write(b"".join(blobs))


def main():
    out = HERE
    logo = rounded(ImageEnhance.Contrast(panda_square(512)).enhance(1.05))
    logo.save(os.path.join(out, "panda-logo.png"))

    mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    mac.alpha_composite(app_icon(824), (100, 100))
    mac.save(os.path.join(out, "icon-1024.png"))

    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    write_ico([app_icon(n, badge=n >= 40) for n in sizes], os.path.join(out, "keymorph.ico"))

    installer = os.path.join(out, "installer")
    os.makedirs(installer, exist_ok=True)
    for w, h in ((164, 314), (246, 471), (328, 628)):
        wizard_banner(w, h).convert("RGB").save(os.path.join(installer, f"wizard-{w}x{h}.bmp"), format="BMP")
    for n in (55, 83, 110):
        small = Image.new("RGBA", (n, n), (255, 255, 255, 255))
        small.alpha_composite(app_icon(n, badge=n >= 80))
        small.convert("RGB").save(os.path.join(installer, f"wizard-small-{n}.bmp"), format="BMP")
    print("assets regenerated")


if __name__ == "__main__":
    main()

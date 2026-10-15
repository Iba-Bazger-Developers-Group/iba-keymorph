#!/usr/bin/env python3
"""Generates every IBA KeyMorph image from one panda artwork.

    python3 assets/make-assets.py

If assets/panda-source.png exists (the original IBA panda, ideally square and >= 512 px) it is used as
the picture; otherwise a drawn panda is used. Requires Pillow and the DejaVu Sans Bold font.
"""
import math
import os
import struct
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# IBA palette (matches the Windows/macOS UI theme).
BG_DARK = (11, 21, 18)
BG_GREEN = (22, 64, 44)
RAY = (46, 204, 113)
ACCENT = (46, 125, 91)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background(s, rays=True):
    """Dark green radial glow with soft light rays, like the IBA Publisher logo."""
    glow = Image.radial_gradient("L").resize((int(s * 1.5), int(s * 1.5)), Image.BICUBIC)
    glow = glow.crop((int(s * 0.25), int(s * 0.3), int(s * 1.25), int(s * 1.3)))
    img = Image.composite(Image.new("RGBA", (s, s), BG_DARK + (255,)), Image.new("RGBA", (s, s), BG_GREEN + (255,)), glow)
    if not rays:
        return img
    cx, cy = s / 2, s * 0.45
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    count = 14
    for i in range(count):
        a0 = (i / count) * 2 * math.pi
        a1 = a0 + math.pi / count * 0.55
        r = s * 1.2
        draw.polygon(
            [(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))],
            fill=RAY + (60 if i % 2 else 34,),
        )
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(s * 0.02)))


def drawn_panda(s):
    """A friendly panda face on a transparent layer of size s."""
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    black = (20, 22, 22, 255)

    def ell(cx, cy, rx, ry, fill):
        d.ellipse([(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s], fill=fill)

    # Ears.
    ell(0.235, 0.215, 0.115, 0.115, black)
    ell(0.765, 0.215, 0.115, 0.115, black)
    ell(0.235, 0.215, 0.055, 0.055, (60, 64, 64, 255))
    ell(0.765, 0.215, 0.055, 0.055, (60, 64, 64, 255))

    # Head with a soft shade towards the chin.
    head = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    hd = ImageDraw.Draw(head)
    hd.ellipse([0.155 * s, 0.17 * s, 0.845 * s, 0.79 * s], fill=(246, 246, 242, 255))
    shade = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse([0.2 * s, 0.55 * s, 0.8 * s, 0.86 * s], fill=(200, 205, 200, 90))
    shade = shade.filter(ImageFilter.GaussianBlur(s * 0.04))
    head = Image.alpha_composite(head, Image.composite(shade, Image.new("RGBA", (s, s)), head))
    layer = Image.alpha_composite(layer, head)
    d = ImageDraw.Draw(layer)

    # Eye patches, tilted outwards.
    for side in (-1, 1):
        patch = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(patch).ellipse([0.405 * s, 0.355 * s, 0.595 * s, 0.6 * s], fill=black)
        patch = patch.rotate(side * -28, center=(s / 2, 0.48 * s), resample=Image.BICUBIC)
        patch = patch.transform(patch.size, Image.AFFINE, (1, 0, side * 0.125 * s, 0, 1, 0), resample=Image.BICUBIC)
        layer = Image.alpha_composite(layer, patch)
    d = ImageDraw.Draw(layer)

    # Eyes with a highlight.
    for cx in (0.37, 0.63):
        ell(cx, 0.465, 0.038, 0.04, (255, 255, 255, 255))
        ell(cx + 0.004, 0.47, 0.024, 0.026, black)
        ell(cx - 0.01, 0.455, 0.009, 0.009, (255, 255, 255, 255))

    # Nose and mouth.
    d.rounded_rectangle([0.455 * s, 0.575 * s, 0.545 * s, 0.628 * s], radius=0.025 * s, fill=black)
    w = max(1, int(0.012 * s))
    d.arc([0.43 * s, 0.6 * s, 0.505 * s, 0.68 * s], 20, 160, fill=black, width=w)
    d.arc([0.495 * s, 0.6 * s, 0.57 * s, 0.68 * s], 20, 160, fill=black, width=w)

    # Rosy cheeks.
    cheeks = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(cheeks).ellipse([0.255 * s, 0.57 * s, 0.335 * s, 0.63 * s], fill=(255, 140, 150, 90))
    ImageDraw.Draw(cheeks).ellipse([0.665 * s, 0.57 * s, 0.745 * s, 0.63 * s], fill=(255, 140, 150, 90))
    layer = Image.alpha_composite(layer, cheeks.filter(ImageFilter.GaussianBlur(s * 0.01)))
    return layer


def panda_art(s, close_up=False):
    """Square panda picture (background + panda) of size s; close_up fills the frame with the head."""
    source = os.path.join(HERE, "panda-source.png")
    if os.path.exists(source):
        img = Image.open(source).convert("RGBA")
        side = min(img.size)
        left, top = (img.width - side) // 2, (img.height - side) // 2
        if close_up:
            inset = side // 8
            left, top, side = left + inset, top + inset // 2, side - 2 * inset
        return img.crop((left, top, left + side, top + side)).resize((s, s), Image.LANCZOS)

    k = 4
    big = s * k
    art = background(big, rays=not close_up)
    if close_up:
        panda = drawn_panda(int(big * 1.3))
        art.alpha_composite(panda, (int(-big * 0.15), int(-big * 0.1)))
    else:
        panda = drawn_panda(int(big * 0.92))
        art.alpha_composite(panda, (int(big * 0.04), 0))
    return art.resize((s, s), Image.LANCZOS)


def swap_badge(img, s, scale=1.0):
    """'A ⇄ Я' badge across the bottom of the picture."""
    d = ImageDraw.Draw(img)
    h = int(s * 0.25 * scale)
    top = s - h - int(s * 0.03)
    pad = int(s * 0.08)
    d.rounded_rectangle([pad, top, s - pad, top + h], radius=h // 2, fill=(11, 21, 18, 225), outline=RAY + (255,), width=max(1, s // 96))
    font = ImageFont.truetype(FONT, int(h * 0.72))
    cy = top + h / 2
    for text, cx in (("A", s * 0.3), ("Я", s * 0.7)):
        box = d.textbbox((0, 0), text, font=font)
        d.text((cx - (box[2] - box[0]) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1]), text, font=font, fill=WHITE)
    # Double arrow.
    lw = max(1, int(h * 0.09))
    x0, x1, a = s * 0.41, s * 0.59, h * 0.14
    for y, direction in ((cy - h * 0.12, 1), (cy + h * 0.12, -1)):
        d.line([(x0, y), (x1, y)], fill=RAY + (255,), width=lw)
        tip = x1 if direction == 1 else x0
        d.polygon([(tip + direction * a * 0.4, y), (tip - direction * a, y - a), (tip - direction * a, y + a)], fill=RAY + (255,))


def rounded(img, radius_ratio=0.22):
    s = img.width
    mask = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1], radius=int(s * 4 * radius_ratio), fill=255)
    mask = mask.resize((s, s), Image.LANCZOS)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def app_icon(s, badge=True):
    img = panda_art(s, close_up=s <= 32)
    if badge:
        swap_badge(img, s)
    return rounded(img)


def save_bmp(img, path):
    img.convert("RGB").save(path, format="BMP")


def main():
    out = HERE

    # UI header logo (panda only) and the macOS icon (Apple guidelines leave ~10% margin).
    rounded(panda_art(512)).save(os.path.join(out, "panda-logo.png"))
    mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    mac.alpha_composite(app_icon(824), (100, 100))
    mac.save(os.path.join(out, "icon-1024.png"))

    # Windows .ico: small sizes show just the panda (the badge would be unreadable).
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [app_icon(n, badge=n >= 40) for n in sizes]
    write_ico(frames, os.path.join(out, "keymorph.ico"))

    # Inno Setup wizard images (100%, 150%, 200% DPI).
    installer = os.path.join(out, "installer")
    os.makedirs(installer, exist_ok=True)
    for w, h in ((164, 314), (246, 471), (328, 628)):
        save_bmp(wizard_banner(w, h), os.path.join(installer, f"wizard-{w}x{h}.bmp"))
    for n in (55, 83, 110):
        small = Image.new("RGBA", (n, n), (255, 255, 255, 255))
        small.alpha_composite(app_icon(n, badge=n >= 80))
        save_bmp(small, os.path.join(installer, f"wizard-small-{n}.bmp"))
    print("assets regenerated")


def wizard_banner(w, h):
    k = 2
    img = background(max(w, h) * k).crop((0, 0, w * k, h * k))
    side = int(w * k * 0.82)
    img.alpha_composite(app_icon(side), ((w * k - side) // 2, int(h * k * 0.16)))
    d = ImageDraw.Draw(img)
    for text, size, y, color in (("IBA KeyMorph", 0.105, 0.68, WHITE), ("EN ⇄ RU", 0.075, 0.76, RAY)):
        font = ImageFont.truetype(FONT, int(w * k * size))
        box = d.textbbox((0, 0), text, font=font)
        d.text(((w * k - (box[2] - box[0])) / 2 - box[0], h * k * y), text, font=font, fill=color)
    return img.resize((w, h), Image.LANCZOS)


def write_ico(frames, path):
    """ICO with PNG-compressed frames (supported since Windows Vista)."""
    import io

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


if __name__ == "__main__":
    main()

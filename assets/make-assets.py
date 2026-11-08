#!/usr/bin/env python3
"""Derived IBA KeyMorph images, built from the IBA panda masters in assets/brand/.

    python3 assets/make-assets.py            # needs Pillow

The panda artwork is never redrawn: the masters (copied from the IBA brand folder) are only resized,
cropped and placed on a canvas.

  assets/brand/iba-icon-jade-1024.png          app icon master (panda + IBA.)    -> icon-1024.png (as is)
  assets/brand/panda-jade-staff-sky-1254.png   panda with the staff on a clear sky -> installer banners

Written by this script:
  icon-1024.png         the icon master, unchanged (source of truth for every platform icon)
  icon-macos-1024.png   the same icon in the macOS app-icon tile (824 px rounded square on 1024 px)
  installer/*.bmp       Inno Setup wizard images (tall banner, small square)

Not written here — exported with the brand script (C:\\MyFiles\\iba-branding\\make-icons.ps1), see README:
  keymorph.ico          Windows application / window icon
  panda-logo.png        512 px logo shown in the settings and About windows

Brand colours (IBA brandbook 4.2): Blue #0055FD, Ink #101421, Mist #F0F3FA, Orange #FFA500.
Banner type is Manrope (brand family) when it can be found, otherwise Segoe UI / DejaVu Sans Bold.
"""
import os
import shutil

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_MASTER = os.path.join(HERE, "brand", "iba-icon-jade-1024.png")
SKY_MASTER = os.path.join(HERE, "brand", "panda-jade-staff-sky-1254.png")

BLUE = (0, 85, 253)
INK = (16, 20, 33)
MIST = (240, 243, 250)
ORANGE = (255, 165, 0)
WHITE = (255, 255, 255)

FONT_CANDIDATES = [
    os.environ.get("MANROPE_FONT", ""),
    os.path.join(HERE, "..", "..", "iba-mott", "assets", "fonts", "Manrope-Variable.ttf"),
    "C:/MyFiles/iba-mott/assets/fonts/Manrope-Variable.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size, weight=700):
    for path in FONT_CANDIDATES:
        if path and os.path.exists(path):
            f = ImageFont.truetype(path, size)
            try:
                f.set_variation_by_axes([weight])  # Manrope variable font; ignored by static fonts
            except Exception:
                pass
            return f
    return ImageFont.load_default()


def master(path):
    return Image.open(path).convert("RGB")


def rounded_tile(img, size, radius_ratio=0.2237):
    """Image clipped to a rounded square of `size` px (4x supersampled mask)."""
    img = img.resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius_ratio), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask.resize((size, size), Image.LANCZOS))
    return out


def wizard_banner(w, h):
    """Tall installer banner: the panda with the staff, product name on an ink footer."""
    sky = master(SKY_MASTER)
    crop_w = int(sky.height * w / h)
    left = 215  # most of the staff on the left, the whole head on the right
    art = sky.crop((left, 0, left + crop_w, sky.height)).resize((w * 3, h * 3), Image.LANCZOS)
    footer_h = int(art.height * 0.2)
    banner = art.copy()
    d = ImageDraw.Draw(banner)
    top = banner.height - footer_h
    d.rectangle([0, top, banner.width, banner.height], fill=INK)
    d.rectangle([0, top, banner.width, top + max(3, w // 40)], fill=BLUE)

    pad = int(banner.width * 0.09)
    title = font(int(banner.width * 0.115), 800)
    sub = font(int(banner.width * 0.062), 600)
    y = top + int(footer_h * 0.2)
    d.text((pad, y), "IBA KeyMorph", font=title, fill=WHITE)
    tw = d.textlength("IBA KeyMorph", font=title)
    dot = int(banner.width * 0.03)
    base = y + int(banner.width * 0.115 * 0.93)
    d.ellipse([pad + tw + dot * 0.4, base - dot, pad + tw + dot * 1.4, base], fill=ORANGE)
    d.text((pad, y + int(banner.width * 0.15)), "Раскладка клавиатуры", font=sub, fill=(200, 210, 232))
    return banner.resize((w, h), Image.LANCZOS)


def main():
    shutil.copyfile(ICON_MASTER, os.path.join(HERE, "icon-1024.png"))

    mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    mac.alpha_composite(rounded_tile(master(ICON_MASTER), 824), (100, 100))
    mac.save(os.path.join(HERE, "icon-macos-1024.png"))

    installer = os.path.join(HERE, "installer")
    os.makedirs(installer, exist_ok=True)
    for w, h in ((164, 314), (246, 471), (328, 628)):
        wizard_banner(w, h).save(os.path.join(installer, f"wizard-{w}x{h}.bmp"), format="BMP")
    for n in (55, 83, 110):
        master(ICON_MASTER).resize((n, n), Image.LANCZOS).save(os.path.join(installer, f"wizard-small-{n}.bmp"), format="BMP")
    print("assets regenerated")


if __name__ == "__main__":
    main()

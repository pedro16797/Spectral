#!/usr/bin/env python3
"""Regenerate every platform icon from the master vector at resources/icon.svg.

The master is a full-bleed 1024x1024 design; each platform gets the treatment
it expects:
  - resources/icon*.png          canonical rasters (also consumed by
                                 flutter_launcher_icons, see pubspec.yaml)
  - Android mipmaps              legacy rounded PNGs + adaptive fg/bg/monochrome
                                 layers (the anydpi-v26 XMLs live in the repo)
  - iOS AppIcon.appiconset       opaque full-bleed, sizes read from Contents.json
  - macOS AppIcon.appiconset     Big Sur style: inset rounded square + shadow
  - web                          favicon, PWA icons, full-bleed maskable icons
  - windows                      multi-size app_icon.ico

Requires: Pillow (pip install pillow) and a Chromium/Chrome binary to
rasterize the SVG (override with CHROMIUM=/path/to/chrome).

Usage: python3 scripts/generate_icons.py   (from the repo root)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024
# Headless Chromium reserves vertical space for window chrome; oversize and crop.
CHROME_PAD = 200
CORNER = 200 / 1024  # corner radius fraction for rounded (non-masked) contexts
ANDROID_DPIS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def find_chromium():
    candidates = [os.environ.get("CHROMIUM"), "chromium", "chromium-browser",
                  "google-chrome", "chrome", "/opt/pw-browsers/chromium"]
    for c in candidates:
        if c and shutil.which(c):
            return shutil.which(c)
    sys.exit("No Chromium/Chrome found; set CHROMIUM=/path/to/chrome")


def render(svg_markup, chromium, workdir, name):
    """Rasterize SVG markup to a transparent 1024x1024 RGBA image."""
    svg_path = os.path.join(workdir, f"{name}.svg")
    html_path = os.path.join(workdir, f"{name}.html")
    shot_path = os.path.join(workdir, f"{name}.png")
    with open(svg_path, "w") as f:
        f.write(svg_markup)
    with open(html_path, "w") as f:
        f.write(
            "<!doctype html><html><head><style>*{margin:0;padding:0}"
            "html,body{overflow:hidden;background:transparent}"
            f"img{{display:block;width:{SIZE}px;height:{SIZE}px}}</style></head>"
            f'<body><img src="file://{svg_path}"></body></html>'
        )
    subprocess.run(
        [chromium, "--headless=new", "--disable-gpu", "--no-sandbox",
         "--hide-scrollbars", "--default-background-color=00000000",
         f"--window-size={SIZE},{SIZE + CHROME_PAD}",
         f"--screenshot={shot_path}", html_path],
        check=True, capture_output=True)
    return Image.open(shot_path).convert("RGBA").crop((0, 0, SIZE, SIZE))


def derive_variants(master_svg):
    """Split the master SVG into foreground / background / monochrome layers."""
    import re

    defs = master_svg.split("<defs>")[1].split("</defs>")[0]
    body = master_svg.split("</defs>")[1].rsplit("</svg>")[0]
    mark = body.split('fill="url(#bgGlow)"/>')[1]

    # Adaptive-icon layers keep the mark inside the 66/108dp safe zone.
    scale = 'transform="translate(512 512) scale(0.9) translate(-512 -512)"'
    head = f'<svg width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}" xmlns="http://www.w3.org/2000/svg">'

    fg = f"{head}<defs>{defs}</defs><g {scale}>{mark}</g></svg>"
    bg = (f"{head}<defs>{defs}</defs>"
          f'<rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>'
          f'<rect width="{SIZE}" height="{SIZE}" fill="url(#bgGlow)"/></svg>')

    mono_mark = re.sub(r'<g filter="url\(#glow\)"[^>]*>.*?</g>', "", mark, flags=re.S)
    mono_mark = re.sub(r"url\(#(ring|wave)\)", "white", mono_mark)
    mono_mark = mono_mark.replace("#AEE2FF", "white")
    mono = f"{head}<g {scale}>{mono_mark}</g></svg>"
    return fg, bg, mono


def rounded(im, frac=CORNER):
    s = im.size[0]
    mask = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, s * 4 - 1, s * 4 - 1], radius=int(s * 4 * frac), fill=255)
    out = im.copy()
    out.putalpha(mask.resize((s, s), Image.LANCZOS))
    return out


def save(im, size, path, mode="RGBA"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.resize((size, size), Image.LANCZOS).convert(mode).save(path)


def main():
    chromium = find_chromium()
    with open(os.path.join(ROOT, "resources/icon.svg")) as f:
        master_svg = f.read()
    fg_svg, bg_svg, mono_svg = derive_variants(master_svg)

    with tempfile.TemporaryDirectory() as workdir:
        master = render(master_svg, chromium, workdir, "master")
        fg = render(fg_svg, chromium, workdir, "fg")
        bg = render(bg_svg, chromium, workdir, "bg")
        mono = render(mono_svg, chromium, workdir, "mono")

    master_rounded = rounded(master)

    # Canonical rasters.
    master.save(os.path.join(ROOT, "resources/icon.png"))
    fg.save(os.path.join(ROOT, "resources/icon_foreground.png"))
    bg.save(os.path.join(ROOT, "resources/icon_background.png"))
    mono.save(os.path.join(ROOT, "resources/icon_monochrome.png"))

    # Android: legacy rounded mipmaps + adaptive layers.
    res = os.path.join(ROOT, "android/app/src/main/res")
    for dpi, k in ANDROID_DPIS.items():
        for name in ("launcher_icon", "ic_launcher"):
            save(master_rounded, int(48 * k), f"{res}/mipmap-{dpi}/{name}.png")
        save(fg, int(108 * k), f"{res}/mipmap-{dpi}/launcher_icon_foreground.png")
        save(bg, int(108 * k), f"{res}/mipmap-{dpi}/launcher_icon_background.png")
        save(mono, int(108 * k), f"{res}/mipmap-{dpi}/launcher_icon_monochrome.png")

    # iOS: opaque full-bleed, sizes taken from the asset catalog.
    iconset = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    with open(os.path.join(iconset, "Contents.json")) as f:
        for img in json.load(f)["images"]:
            px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
            save(master, px, os.path.join(iconset, img["filename"]), mode="RGB")

    # macOS: Big Sur style — 824px rounded content on a 1024 canvas with shadow.
    content = rounded(master, frac=185 / 824).resize((824, 824), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(sh_mask).rounded_rectangle([100, 110, 923, 933], radius=185, fill=110)
    shadow.putalpha(sh_mask.filter(ImageFilter.GaussianBlur(18)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(content, (100, 100), content)
    for s in (16, 32, 64, 128, 256, 512, 1024):
        save(canvas, s,
             os.path.join(ROOT, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{s}.png"))

    # Web: rounded favicon/PWA icons, full-bleed maskable icons.
    save(master_rounded, 32, os.path.join(ROOT, "web/favicon.png"))
    save(master_rounded, 192, os.path.join(ROOT, "web/icons/Icon-192.png"))
    save(master_rounded, 512, os.path.join(ROOT, "web/icons/Icon-512.png"))
    save(master, 192, os.path.join(ROOT, "web/icons/Icon-maskable-192.png"))
    save(master, 512, os.path.join(ROOT, "web/icons/Icon-maskable-512.png"))

    # Windows: multi-size ICO.
    master_rounded.resize((256, 256), Image.LANCZOS).save(
        os.path.join(ROOT, "windows/runner/resources/app_icon.ico"),
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    print("All platform icons regenerated from resources/icon.svg")


if __name__ == "__main__":
    main()

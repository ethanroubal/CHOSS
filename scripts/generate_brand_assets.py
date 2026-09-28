#!/usr/bin/env python3
"""Build the app's brand assets from the source logos in brand/.

  pip install pillow numpy
  python3 scripts/generate_brand_assets.py

Writes into CHOSS/Assets.xcassets:
  AppIcon      1024x1024 full-bleed icon (iOS applies its own corner mask)
  AppLogo      the rounded-square icon with transparent corners (splash, empty states)
  HoldMark     the climbing-hold shape alone, as a tintable template (tab bar, small marks)
  Wordmark     "CHOSS" on transparent: forest green in light mode, cream in dark mode
  BrandGreen / BrandCream color sets
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand"
ASSETS = ROOT / "CHOSS" / "Assets.xcassets"

GREEN = np.array([29, 42, 30])     # sampled from the logos
CREAM = np.array([243, 237, 225])


def write_contents(folder: Path, contents: dict):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def luminance(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def crop_to_alpha(img: Image.Image, pad: int) -> Image.Image:
    left, top, right, bottom = img.getchannel("A").getbbox()
    return img.crop((max(left - pad, 0), max(top - pad, 0),
                     min(right + pad, img.width), min(bottom + pad, img.height)))


# --- Wordmark ------------------------------------------------------------------

def wordmark():
    src = np.asarray(Image.open(BRAND / "choss-wordmark-source.png").convert("RGB")).astype(float)
    lum = luminance(src)
    # Letters are dark on white: full alpha below 160, fading out to white at 235 (anti-aliased edges).
    alpha = np.clip((235 - lum) / (235 - 160), 0, 1)

    # Light mode: original stone texture. Edge pixels get pure green so no white fringe.
    light = src.copy()
    edge = alpha < 1
    light[edge] = GREEN

    # Dark mode: cream letters; the lighter speckles of the texture become slightly darker cream.
    texture = np.clip((lum - 30) / 110, 0, 1)[..., None]
    dark = CREAM * (1 - 0.3 * texture)
    dark[edge] = CREAM

    folder = ASSETS / "Wordmark.imageset"
    images = []
    for name, rgb, appearance in (("wordmark-light.png", light, None), ("wordmark-dark.png", dark, "dark")):
        rgba = np.dstack([rgb, alpha * 255]).round().astype(np.uint8)
        img = crop_to_alpha(Image.fromarray(rgba, "RGBA"), pad=8)
        img = img.resize((1200, round(img.height * 1200 / img.width)), Image.LANCZOS)
        folder.mkdir(parents=True, exist_ok=True)
        img.save(folder / name, optimize=True)
        entry = {"filename": name, "idiom": "universal"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    write_contents(folder, {"images": images, "info": {"author": "xcode", "version": 1}})


# --- Icon ------------------------------------------------------------------------

def icon_square():
    """The source icon cropped to its rounded square, plus a mask of the white outside corners."""
    src = np.asarray(Image.open(BRAND / "choss-icon-source.png").convert("RGB")).astype(float)
    ys, xs = np.where(src.sum(axis=2) < 700)
    square = src[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    size = min(square.shape[:2])
    square = square[:size, :size]

    # White pixels near the four corners are outside the rounded shape.
    corner = int(size * 0.2)
    near_corner = np.zeros((size, size), bool)
    for y in (slice(0, corner), slice(size - corner, size)):
        for x in (slice(0, corner), slice(size - corner, size)):
            near_corner[y, x] = True
    whiteness = np.clip((square.sum(axis=2) - 500) / 240, 0, 1)
    outside = np.where(near_corner, whiteness, 0)
    return square, outside


def app_icon(square, outside):
    # Full bleed: paint the white corners green; iOS masks the corners itself.
    rgb = square * (1 - outside[..., None]) + GREEN * outside[..., None]
    img = Image.fromarray(rgb.round().astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
    folder = ASSETS / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    img.save(folder / "AppIcon.png", optimize=True)
    write_contents(folder, {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })


def app_logo(square, outside):
    alpha = (1 - outside) * 255
    rgba = np.dstack([square, alpha]).round().astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA").resize((600, 600), Image.LANCZOS)
    folder = ASSETS / "AppLogo.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    img.save(folder / "app-logo.png", optimize=True)
    write_contents(folder, {
        "images": [{"filename": "app-logo.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })


def hold_mark(square):
    # The cream hold is the bright area inside the (dark) square.
    lum = luminance(square)
    mask = Image.fromarray((np.clip((lum - 90) / 80, 0, 1) * 255).astype(np.uint8), "L")
    # Drop the white outside corners: only keep what's well inside the square.
    size = mask.width
    inner = Image.new("L", mask.size, 0)
    inner.paste(255, (int(size * 0.12), int(size * 0.12), int(size * 0.88), int(size * 0.88)))
    mask = Image.fromarray(np.minimum(np.asarray(mask), np.asarray(inner)))
    # Close the small dark speckles so the mark reads cleanly at tab-bar size.
    mask = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))

    rgba = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    rgba.putalpha(mask)
    rgba = crop_to_alpha(rgba, pad=4)
    side = max(rgba.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))

    folder = ASSETS / "HoldMark.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    # 25pt, the standard tab-bar glyph size.
    for scale in (1, 2, 3):
        name = f"hold-mark@{scale}x.png"
        canvas.resize((25 * scale, 25 * scale), Image.LANCZOS).save(folder / name, optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    write_contents(folder, {
        "images": images,
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    })
    # A large version for splash / empty states, tinted in code.
    big = ASSETS / "HoldMarkLarge.imageset"
    big.mkdir(parents=True, exist_ok=True)
    canvas.resize((360, 360), Image.LANCZOS).save(big / "hold-mark-large.png", optimize=True)
    write_contents(big, {
        "images": [{"filename": "hold-mark-large.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    })


# --- Colors ------------------------------------------------------------------------

def color(rgb):
    r, g, b = (f"{c / 255:.3f}" for c in rgb)
    return {"color-space": "srgb", "components": {"red": r, "green": g, "blue": b, "alpha": "1.000"}}


def color_set(name, light, dark=None):
    colors = [{"idiom": "universal", "color": color(light)}]
    if dark is not None:
        colors.append({"idiom": "universal", "color": color(dark),
                       "appearances": [{"appearance": "luminosity", "value": "dark"}]})
    write_contents(ASSETS / f"{name}.colorset", {"colors": colors, "info": {"author": "xcode", "version": 1}})


def colors():
    color_set("BrandGreen", GREEN)
    color_set("BrandCream", CREAM)
    # Accent: a slightly lifted forest green so selected tabs/links stand out from black text;
    # a lighter sage in dark mode so it stays readable on black.
    color_set("AccentColor", (47, 82, 56), (127, 168, 134))
    # Text/icons drawn on top of the accent color: white on dark green, forest green on sage.
    color_set("OnAccent", (255, 255, 255), GREEN)


if __name__ == "__main__":
    wordmark()
    square, outside = icon_square()
    app_icon(square, outside)
    app_logo(square, outside)
    hold_mark(square)
    colors()
    print("Brand assets written to", ASSETS)

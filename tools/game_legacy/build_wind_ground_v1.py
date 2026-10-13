"""Normalize the approved wind-ground cutouts and record their walk lines.

Run from the repository root after updating a *_source.png candidate. The
surface coordinates below are read from the painted moss edge in each source,
not from the highest leaf, which is often above the actual walkable surface.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/sideview/environment/chapter_1_wind/terrain/ground_v1"
PREVIEW = ROOT / "docs/art_prompts/chapter_1_wind"
ART_SCALE = 1.3
PAD = 6

# output name: (source name, output width, original painted walk-line y at
# the left and right solid ends). Do not flip art to make another direction:
# the light must always come from the upper left.
PIECES = {
    "wind_ground_long": ("long_source.png", 420, 274, 274),
    "wind_ground_short": ("short_source.png", 220, 344, 344),
    "wind_ground_edge_left": ("edge_left_source.png", 310, 315, 315),
    "wind_ground_edge_right": ("edge_right_source.png", 260, 250, 250),
    "wind_ground_slope_up": ("slope_up_source.png", 220, 524, 177),
    "wind_ground_slope_down": ("slope_down_source.png", 220, 254, 484),
    "wind_ground_crumble": ("crumble_source.png", 220, 330, 330),
}


def normalize(name: str, source: str, width: int, left_y: int, right_y: int):
    original = Image.open(KIT / "candidates" / source).convert("RGBA")
    alpha = original.getchannel("A").point(lambda value: 255 if value >= 24 else 0)
    box = alpha.getbbox()
    if box is None:
        raise ValueError(f"{source} has no visible pixels")
    cutout = original.crop(box)
    factor = (width - 2 * PAD) / cutout.width
    height = round(cutout.height * factor) + 2 * PAD
    scaled = cutout.resize((width - 2 * PAD, height - 2 * PAD), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (PAD, PAD))
    path = KIT / f"{name}.png"
    canvas.save(path, optimize=True)

    top_left = round(PAD + (left_y - box[1]) * factor, 1)
    top_right = round(PAD + (right_y - box[1]) * factor, 1)
    solid_x = [float(PAD), float(width - PAD)]
    profile = {
        "fit_slope": round((top_right - top_left) / (solid_x[1] - solid_x[0]), 3),
        "median_top": round((top_left + top_right) / 2, 1),
        "size": [width, height],
        "solid_x": solid_x,
        "top_left": top_left,
        "top_right": top_right,
    }
    return canvas, profile


def normalize_wall():
    source = Image.open(KIT / "candidates/wall_source.png").convert("RGB")
    # Overlap the original panel with its next copy. At the exported tile's
    # boundary the source rows are adjacent, so there is no bright seam band.
    width, period, overlap = 147, 214, 66
    extended = source.resize((width, period + overlap), Image.Resampling.LANCZOS)
    wall = extended.crop((0, 0, width, period))
    pixels = wall.load()
    extended_pixels = extended.load()
    for y in range(overlap):
        top_weight = 0.5 - 0.5 * math.cos(math.pi * y / (overlap - 1))
        for x in range(width):
            top = extended_pixels[x, y]
            bottom = extended_pixels[x, y + period]
            pixels[x, y] = tuple(
                round(bottom[c] * (1 - top_weight) + top[c] * top_weight)
                for c in range(3)
            )
    wall.save(KIT / "wind_ground_wall.png", optimize=True)
    return wall


def checkerboard(size):
    image = Image.new("RGBA", size, (118, 143, 148, 255))
    draw = ImageDraw.Draw(image)
    step = 24
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2:
                draw.rectangle((x, y, x + step - 1, y + step - 1), fill=(129, 153, 157, 255))
    return image


def preview_font():
    try:
        return ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 19)
    except OSError:
        return ImageFont.load_default()


def write_preview(images, profiles, wall):
    scale = ART_SCALE
    sheet = checkerboard((1360, 820))
    draw = ImageDraw.Draw(sheet)
    font = preview_font()
    positions = {
        "wind_ground_long": (55, 72),
        "wind_ground_short": (730, 72),
        "wind_ground_edge_left": (55, 255),
        "wind_ground_edge_right": (730, 255),
        "wind_ground_slope_up": (55, 438),
        "wind_ground_slope_down": (730, 438),
        "wind_ground_crumble": (55, 625),
    }
    for name, (x, y) in positions.items():
        image = images[name]
        rendered = image.resize(
            (round(image.width * scale), round(image.height * scale)),
            Image.Resampling.LANCZOS,
        )
        sheet.alpha_composite(rendered, (x, y))
        info = profiles[f"{name}.png"]
        x0 = x + round(info["solid_x"][0] * scale)
        x1 = x + round(info["solid_x"][1] * scale)
        y0 = y + round(info["top_left"] * scale)
        y1 = y + round(info["top_right"] * scale)
        draw.line((x0, y0, x1, y1), fill=(43, 236, 244, 255), width=2)
        draw.text((x, y - 28), name.removeprefix("wind_ground_"), font=font, fill=(250, 251, 245, 255))
    wall_rendered = wall.resize((round(wall.width * scale), round(wall.height * scale)), Image.Resampling.LANCZOS)
    sheet.alpha_composite(wall_rendered.convert("RGBA"), (1085, 495))
    draw.text((1085, 467), "wall", font=font, fill=(250, 251, 245, 255))
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(PREVIEW / "wind_ground_v1_preview.png", optimize=True)


def write_tiling_preview(images, profiles, wall):
    sheet = checkerboard((1500, 1050))
    draw = ImageDraw.Draw(sheet)
    font = preview_font()
    draw.text((35, 20), "flat run: long + short + long (34 px overlap)", font=font, fill="white")
    baseline = 230
    start = 35.0
    for name in ("wind_ground_long", "wind_ground_short", "wind_ground_long"):
        source = images[name]
        info = profiles[f"{name}.png"]
        rendered = source.resize(
            (round(source.width * ART_SCALE), round(source.height * ART_SCALE)),
            Image.Resampling.LANCZOS,
        )
        x = round(start - info["solid_x"][0] * ART_SCALE)
        y = round(baseline - info["median_top"] * ART_SCALE)
        sheet.alpha_composite(rendered, (x, y))
        start += (info["solid_x"][1] - info["solid_x"][0]) * ART_SCALE - 34
    draw.line((35, baseline, 1450, baseline), fill=(43, 236, 244, 255), width=2)
    draw.text((35, 325), "wall repeated vertically", font=font, fill="white")
    scaled_wall = wall.resize((160, round(wall.height * 160 / wall.width)), Image.Resampling.LANCZOS)
    for index in range(3):
        sheet.alpha_composite(scaled_wall.convert("RGBA"), (35, 360 + index * (scaled_wall.height - 24)))
    sheet.convert("RGB").save(PREVIEW / "wind_ground_v1_tiling.png", optimize=True)


def main():
    KIT.mkdir(parents=True, exist_ok=True)
    images = {}
    profiles = {}
    for name, spec in PIECES.items():
        image, profile = normalize(name, *spec)
        images[name] = image
        profiles[f"{name}.png"] = profile
    wall = normalize_wall()
    (KIT / "surfaces.json").write_text(
        json.dumps(profiles, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    write_preview(images, profiles, wall)
    write_tiling_preview(images, profiles, wall)


if __name__ == "__main__":
    main()

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


SOURCE = Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧")
OUTPUT = SOURCE / "normalized-v1"
CANVAS = (192, 192)
BASELINE_Y = 176
SOURCE_SCALE = 68 / 128  # 271 px concept renders -> original 128 px asset scale
SOURCE_CENTER_X = 271 / 2
SOURCE_BASELINE_Y = 558


def remove_pale_background(im: Image.Image) -> Image.Image:
    """Derive alpha against the concept sheet's nearly x-uniform pale backdrop."""
    rgb = im.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    bg = Image.new("RGB", rgb.size)
    bp = bg.load()
    for y in range(h):
        samples = [px[x, y] for x in list(range(0, 14)) + list(range(w - 14, w))]
        samples.sort(key=lambda c: sum(c))
        c = samples[len(samples) // 2]
        for x in range(w):
            bp[x, y] = c

    diff = ImageChops.difference(rgb, bg)
    dpx = diff.load()
    alpha = Image.new("L", rgb.size, 0)
    apx = alpha.load()
    for y in range(h):
        for x in range(w):
            d = max(dpx[x, y])
            # Soft edge: suppress background noise, retain antialiasing and the contact shadow.
            apx[x, y] = 0 if d <= 5 else 255 if d >= 25 else round((d - 5) * 255 / 20)
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def place_original(im: Image.Image) -> Image.Image:
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - im.width) // 2
    y = BASELINE_Y - 139  # preserve original pixels; original visible feet end at y=138
    out.alpha_composite(im.convert("RGBA"), (x, y))
    return out


def place_concept(im: Image.Image) -> Image.Image:
    cutout = remove_pale_background(im)
    scaled = cutout.resize(
        (round(cutout.width * SOURCE_SCALE), round(cutout.height * SOURCE_SCALE)),
        Image.Resampling.LANCZOS,
    )
    x = round(CANVAS[0] / 2 - SOURCE_CENTER_X * SOURCE_SCALE)
    y = round(BASELINE_Y - SOURCE_BASELINE_Y * SOURCE_SCALE)
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(scaled, (x, y))
    return out


def make_preview(frames: list[tuple[str, Image.Image]]) -> Image.Image:
    tile_w, tile_h = 224, 232
    preview = Image.new("RGBA", (tile_w * len(frames), tile_h), (238, 238, 238, 255))
    draw = ImageDraw.Draw(preview)
    for i, (name, frame) in enumerate(frames):
        ox = i * tile_w + 16
        oy = 16
        # Checkerboard exists only in the preview, never in normalized assets.
        for yy in range(0, CANVAS[1], 12):
            for xx in range(0, CANVAS[0], 12):
                c = (215, 215, 215, 255) if (xx // 12 + yy // 12) % 2 else (244, 244, 244, 255)
                draw.rectangle((ox + xx, oy + yy, ox + xx + 11, oy + yy + 11), fill=c)
        preview.alpha_composite(frame, (ox, oy))
        draw.line((ox, oy + BASELINE_Y, ox + CANVAS[0] - 1, oy + BASELINE_Y), fill=(220, 70, 65, 255), width=1)
        draw.text((ox, 212), name, fill=(25, 25, 25, 255), anchor="la")
    return preview


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = []
    for name in ("1", "3", "5", "8"):
        src = Image.open(SOURCE / f"{name}.png")
        normalized = place_original(src) if name in {"1", "8"} else place_concept(src)
        normalized.save(OUTPUT / f"{name}.png")
        result.append((name, normalized))
    make_preview(result).save(OUTPUT / "preview.png")


if __name__ == "__main__":
    main()

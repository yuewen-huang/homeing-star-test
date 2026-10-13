from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "PendingArt" / "character" / "师傅" / "手工绑骨作业区" / "最终成品" / "风魔法FX" / "my-art-sp-atak.png"
BACKGROUND = ROOT / "assets" / "sideview" / "environment" / "tutorial_city_gate" / "01_far_city_wide_v2.png"
OUTPUT = ROOT / "PendingArt" / "character" / "师傅" / "手工绑骨作业区" / "最终成品" / "风魔法FX" / "palette-review.png"

FRAME_SIZE = (576, 256)
FRAME_INDEX = 12

PALETTES = {
    "ORIGINAL": None,
    "A  COLD STEEL BLUE": (
        (4, 20, 45), (9, 66, 112), (20, 137, 178), (91, 205, 221), (205, 239, 235)
    ),
    "B  RESTRAINED JADE": (
        (5, 28, 40), (8, 76, 87), (23, 137, 132), (93, 195, 173), (206, 236, 207)
    ),
    "C  BLUE VIOLET WIND": (
        (18, 17, 54), (43, 55, 117), (60, 121, 174), (126, 196, 221), (218, 235, 239)
    ),
}

POSITIONS = np.array([0.0, 0.22, 0.50, 0.76, 1.0], dtype=np.float32)


def extract_frame(sheet: Image.Image) -> Image.Image:
    columns = sheet.width // FRAME_SIZE[0]
    x = (FRAME_INDEX % columns) * FRAME_SIZE[0]
    y = (FRAME_INDEX // columns) * FRAME_SIZE[1]
    return sheet.crop((x, y, x + FRAME_SIZE[0], y + FRAME_SIZE[1]))


def recolor(frame: Image.Image, palette) -> Image.Image:
    if palette is None:
        return frame.copy()
    rgba = np.asarray(frame.convert("RGBA"), dtype=np.uint8)
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    alpha = rgba[..., 3]
    luminance = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    value = rgb.max(axis=2)
    energy = np.clip(0.52 * value + 0.48 * luminance, 0.0, 1.0)
    colors = np.asarray(palette, dtype=np.float32)
    mapped = np.empty((*energy.shape, 3), dtype=np.float32)
    for channel in range(3):
        mapped[..., channel] = np.interp(energy, POSITIONS, colors[:, channel])
    output = np.zeros_like(rgba)
    output[..., :3] = np.rint(mapped).clip(0, 255).astype(np.uint8)
    output[..., 3] = alpha
    output[alpha == 0, :3] = 0
    return Image.fromarray(output, "RGBA")


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    frame = extract_frame(source)
    background = Image.open(BACKGROUND).convert("RGBA")
    background = ImageOps.fit(background, FRAME_SIZE, method=Image.Resampling.LANCZOS, centering=(0.55, 0.45))
    # Dim the scenery slightly to approximate combat readability without
    # changing the effect itself.
    backdrop = Image.blend(background, Image.new("RGBA", FRAME_SIZE, (22, 31, 39, 255)), 0.28)

    label_h = 34
    panel_w, panel_h = FRAME_SIZE[0], FRAME_SIZE[1] + label_h
    canvas = Image.new("RGBA", (panel_w * len(PALETTES), panel_h), (12, 18, 23, 255))
    draw = ImageDraw.Draw(canvas)
    for index, (label, palette) in enumerate(PALETTES.items()):
        panel = backdrop.copy()
        panel.alpha_composite(recolor(frame, palette))
        x = index * panel_w
        canvas.alpha_composite(panel, (x, label_h))
        draw.rectangle((x, 0, x + panel_w, label_h), fill=(12, 18, 23, 255))
        draw.text((x + 14, 10), label, fill=(225, 234, 236, 255))
        if index:
            draw.line((x, 0, x, panel_h), fill=(75, 91, 99, 255), width=1)
    canvas.save(OUTPUT)
print("palette-review.png")


if __name__ == "__main__":
    main()

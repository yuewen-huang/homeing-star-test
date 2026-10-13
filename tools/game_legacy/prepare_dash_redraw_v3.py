from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = Path(
    "D:/CodexData/.codex/generated_images/01a08bf6-53aa-78c1-824b-9c341b6c0f6c/"
    "exec-92c97d85-b037-4b7e-a36c-50741effbe7d.png"
)
OUTPUT = Path("PendingArt/character/师傅/BOSS形态/采用/冲刺/dash-continuity-fixed-v3")
FRAME_SIZE = (512, 384)


def foreground_mask(rgb: Image.Image) -> Image.Image:
    data = np.asarray(rgb).astype(np.int16)
    maximum = data.max(axis=2)
    minimum = data.min(axis=2)
    chroma = maximum - minimum
    # Checkerboard is bright neutral gray. Character pixels are colored or dark.
    definite = (chroma > 18) | (minimum < 150)
    mask = Image.fromarray((definite * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MaxFilter(3))

    # Restore light sword/fur interiors enclosed by definite foreground outlines.
    flooded = mask.copy()
    draw = ImageDraw.Draw(flooded)
    for seed in ((0, 0), (flooded.width - 1, 0), (0, flooded.height - 1),
                 (flooded.width - 1, flooded.height - 1)):
        ImageDraw.floodfill(flooded, seed, 128, thresh=0)
    values = np.asarray(flooded)
    solid = np.where(values == 128, 0, 255).astype(np.uint8)
    return Image.fromarray(solid, "L")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rgb = Image.open(SOURCE).convert("RGB")
    alpha = foreground_mask(rgb)
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)

    sheet_size = (FRAME_SIZE[0] * 4, FRAME_SIZE[1] * 4)
    sheet = rgba.resize(sheet_size, Image.Resampling.NEAREST)
    sheet.save(OUTPUT / "dash_continuity_fixed_sheet_4x4.png")

    frames = []
    for row in range(4):
        for column in range(4):
            box = (
                column * FRAME_SIZE[0], row * FRAME_SIZE[1],
                (column + 1) * FRAME_SIZE[0], (row + 1) * FRAME_SIZE[1],
            )
            frame = sheet.crop(box)
            number = row * 4 + column + 1
            frame.save(OUTPUT / f"dash_{number:02d}.png")
            preview = Image.new("RGBA", FRAME_SIZE, (24, 24, 24, 255))
            preview.alpha_composite(frame)
            frames.append(preview.convert("RGB"))

    frames[0].save(
        OUTPUT / "dash_continuity_fixed_preview.gif",
        save_all=True,
        append_images=frames[1:],
        duration=100,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    main()

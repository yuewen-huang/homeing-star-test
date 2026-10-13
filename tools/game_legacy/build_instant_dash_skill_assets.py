"""Prepare the approved instant-dash character and effect layers for Godot.

The source character sheet is already palette-correct.  The supplied effect is
three vertically stacked transparent key frames; normalize those cells into a
horizontal Godot sheet with a shared canvas so its center/ground alignment does
not move while it fades.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


CHARACTER_FRAME_SIZE = (192, 64)
CHARACTER_FRAME_COUNT = 15
CHARACTER_COLUMNS = 4
EFFECT_FRAME_SIZE = (384, 128)
EFFECT_FRAME_COUNT = 3


def prepare_effect(source: Path, destination: Path) -> None:
    raw = Image.open(source).convert("RGBA")
    if raw.height % EFFECT_FRAME_COUNT != 0:
        raise ValueError(f"Expected {EFFECT_FRAME_COUNT} stacked effect cells, got {raw.size}")

    source_cell_height = raw.height // EFFECT_FRAME_COUNT
    sheet = Image.new("RGBA", (EFFECT_FRAME_SIZE[0] * EFFECT_FRAME_COUNT, EFFECT_FRAME_SIZE[1]))
    for index in range(EFFECT_FRAME_COUNT):
        cell = raw.crop((0, index * source_cell_height, raw.width, (index + 1) * source_cell_height))
        # Nearest-neighbor keeps the shipped game readable at pixel scale;
        # palette reduction removes the generated high-resolution gradients.
        cell = cell.resize(EFFECT_FRAME_SIZE, Image.Resampling.NEAREST)
        alpha = cell.getchannel("A")
        rgb = cell.convert("RGB").quantize(colors=32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
        rgb.putalpha(alpha)
        sheet.alpha_composite(rgb, (index * EFFECT_FRAME_SIZE[0], 0))

    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--character", type=Path, required=True)
    parser.add_argument("--effect", type=Path, required=True)
    parser.add_argument("--character-out", type=Path, required=True)
    parser.add_argument("--effect-out", type=Path, required=True)
    args = parser.parse_args()

    character = Image.open(args.character).convert("RGBA")
    expected_size = (CHARACTER_FRAME_SIZE[0] * 4, CHARACTER_FRAME_SIZE[1] * 5)
    if character.size != expected_size:
        raise ValueError(f"Expected a 4x5 {CHARACTER_FRAME_SIZE} character sheet, got {character.size}")
    args.character_out.parent.mkdir(parents=True, exist_ok=True)
    # The final five source cels are deliberately rejected: the approved
    # instant-dash recovery ends on frame 15.  Repack the retained frames into
    # a compact 4x4 Godot sheet; its one unused final slot remains transparent.
    output_rows = (CHARACTER_FRAME_COUNT + CHARACTER_COLUMNS - 1) // CHARACTER_COLUMNS
    trimmed_character = Image.new(
        "RGBA",
        (CHARACTER_FRAME_SIZE[0] * CHARACTER_COLUMNS, CHARACTER_FRAME_SIZE[1] * output_rows),
    )
    for index in range(CHARACTER_FRAME_COUNT):
        source_x = (index % 4) * CHARACTER_FRAME_SIZE[0]
        source_y = (index // 4) * CHARACTER_FRAME_SIZE[1]
        frame = character.crop((
            source_x,
            source_y,
            source_x + CHARACTER_FRAME_SIZE[0],
            source_y + CHARACTER_FRAME_SIZE[1],
        ))
        destination_x = (index % CHARACTER_COLUMNS) * CHARACTER_FRAME_SIZE[0]
        destination_y = (index // CHARACTER_COLUMNS) * CHARACTER_FRAME_SIZE[1]
        trimmed_character.alpha_composite(frame, (destination_x, destination_y))
    trimmed_character.save(args.character_out)
    prepare_effect(args.effect, args.effect_out)


if __name__ == "__main__":
    main()

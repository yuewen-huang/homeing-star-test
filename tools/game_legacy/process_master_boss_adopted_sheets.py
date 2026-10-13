from pathlib import Path

from PIL import Image


ROOT = Path(r"E:\homingStarGodot")
SOURCES = {
    "idle": ROOT / r"PendingArt\character\师傅\BOSS形态\采用\待机\ChatGPT Image 2026年9月11日 16_46_40.png",
    "walk": ROOT / r"PendingArt\character\师傅\BOSS形态\采用\走路\ChatGPT Image 2026年9月11日 16_21_03.png",
}
OUTPUTS = {
    "idle": ROOT / r"assets\sideview\characters\master\boss\phase1\idle\master_boss_idle_adopted_128x144_16f.png",
    "walk": ROOT / r"assets\sideview\characters\master\boss\phase1\walk\master_boss_walk_adopted_128x144_16f.png",
}

COLS = 4
ROWS = 4
FRAME_SIZE = (128, 144)
PALETTE_COLORS = 96


def occupied_row_bands(source: Image.Image) -> list[tuple[int, int]]:
    alpha = source.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    bands: list[tuple[int, int]] = []
    band_start: int | None = None
    for y in range(source.height + 1):
        occupied = y < source.height and alpha.crop((0, y, source.width, y + 1)).getbbox() is not None
        if occupied and band_start is None:
            band_start = y
        elif not occupied and band_start is not None:
            bands.append((band_start, y))
            band_start = None
    if len(bands) != ROWS:
        raise ValueError(f"Expected {ROWS} occupied rows, found {bands}")
    return bands


def pixelize_frame(frame: Image.Image) -> Image.Image:
    frame = frame.convert("RGBA")
    output = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))

    scale = min(FRAME_SIZE[0] / frame.width, FRAME_SIZE[1] / frame.height)
    resized_size = (
        max(1, round(frame.width * scale)),
        max(1, round(frame.height * scale)),
    )
    # The adopted sheets already contain deliberate pixel clusters. Nearest
    # neighbour preserves those edges; filtered reduction made them muddy.
    reduced = frame.resize(resized_size, Image.Resampling.NEAREST)

    # Pixel sprites use hard coverage. Keeping the source's hundreds of partial
    # alpha values would preserve the high-resolution anti-aliased fringe and
    # make the result look soft in Godot.
    alpha = reduced.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgb = reduced.convert("RGB").quantize(
        colors=PALETTE_COLORS,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    reduced = Image.merge("RGBA", (*rgb.split(), alpha))

    offset = (
        (FRAME_SIZE[0] - resized_size[0]) // 2,
        FRAME_SIZE[1] - resized_size[1],
    )
    output.alpha_composite(reduced, offset)
    return align_to_ground(output)


def align_to_ground(frame: Image.Image) -> Image.Image:
    """Keep the lowest opaque pixel on a shared baseline across all frames."""
    bounds = frame.getchannel("A").getbbox()
    if bounds is None:
        return frame
    vertical_shift = FRAME_SIZE[1] - bounds[3]
    if vertical_shift == 0:
        return frame
    aligned = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    aligned.alpha_composite(frame, (0, vertical_shift))
    return aligned


def process_sheet(source_path: Path, output_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    row_bands = occupied_row_bands(source)
    source_frame_width = (source.width + COLS - 1) // COLS
    source_frame_height = max(y1 - y0 for y0, y1 in row_bands)
    output = Image.new(
        "RGBA",
        (FRAME_SIZE[0] * COLS, FRAME_SIZE[1] * ROWS),
        (0, 0, 0, 0),
    )

    for row in range(ROWS):
        row_start, row_end = row_bands[row]
        for column in range(COLS):
            x0 = round(column * source.width / COLS)
            x1 = round((column + 1) * source.width / COLS)
            cropped = source.crop((x0, row_start, x1, row_end))
            frame = Image.new(
                "RGBA",
                (source_frame_width, source_frame_height),
                (0, 0, 0, 0),
            )
            frame.alpha_composite(
                cropped,
                (
                    (source_frame_width - cropped.width) // 2,
                    source_frame_height - cropped.height,
                ),
            )
            processed = pixelize_frame(frame)
            output.alpha_composite(
                processed,
                (column * FRAME_SIZE[0], row * FRAME_SIZE[1]),
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output.save(output_path, optimize=True)


if __name__ == "__main__":
    for animation_name, source_path in SOURCES.items():
        process_sheet(source_path, OUTPUTS[animation_name])
        print(OUTPUTS[animation_name])

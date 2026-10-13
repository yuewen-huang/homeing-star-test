"""Import Lan's hand-edited run sheets with a shared transparent frame size."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = (
    ROOT
    / "PendingArt"
    / "character"
    / "主角-岚"
    / "palette-bases"
    / "run"
    / "sprite sheets"
)
TARGET_DIR = ROOT / "assets" / "sideview" / "characters" / "lan" / "run"
FRAME_SIZE = (65, 58)

# source filename, output filename, source frame size, frame count
SHEETS = (
    ("run_start.png", "run_start.png", (59, 53), 2),
    ("run.png", "run.png", (65, 48), 20),
    ("run_turn.png", "run_turn.png", (59, 51), 8),
    ("run_stop-sheet.png", "run_stop.png", (63, 53), 15),
)


def import_sheet(
    source_name: str,
    target_name: str,
    source_frame_size: tuple[int, int],
    frame_count: int,
) -> None:
    source_path = SOURCE_DIR / source_name
    source = Image.open(source_path).convert("RGBA")
    source_width, source_height = source_frame_size
    expected_size = (source_width * frame_count, source_height)
    if source.size != expected_size:
        raise ValueError(
            f"{source_path} is {source.size}, expected {expected_size} "
            f"({frame_count} frames of {source_frame_size})"
        )

    output = Image.new("RGBA", (FRAME_SIZE[0] * frame_count, FRAME_SIZE[1]))
    x_padding = (FRAME_SIZE[0] - source_width) // 2
    y_padding = FRAME_SIZE[1] - source_height
    for frame_index in range(frame_count):
        left = frame_index * source_width
        frame = source.crop((left, 0, left + source_width, source_height))
        output.alpha_composite(
            frame,
            (frame_index * FRAME_SIZE[0] + x_padding, y_padding),
        )

    target_path = TARGET_DIR / target_name
    output.save(target_path)
    print(f"Imported {target_path.relative_to(ROOT)}: {frame_count} x {FRAME_SIZE}")


def main() -> None:
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, target_name, source_frame_size, frame_count in SHEETS:
        import_sheet(source_name, target_name, source_frame_size, frame_count)


if __name__ == "__main__":
    main()

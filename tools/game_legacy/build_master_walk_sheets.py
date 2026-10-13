"""Export the approved master walk start and loop without changing source art."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from build_master_clean_sheets import parse_flattened_aseprite, save_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/最终成品/一阶段画风优化版"
OUTPUT = ROOT / "assets/sideview/characters/master/boss"
START_OUTPUT = OUTPUT / "phase1_optimized_walk_start_256x256_11f.png"
LOOP_OUTPUT = OUTPUT / "phase1_optimized_walking_loop_320x256_10f.png"
SOURCE_FRAME_SIZE = (256, 256)
LOOP_FRAME_SIZE = (320, 256)
LOOP_FRAME_COUNT = 10


def head_center_x(frame: Image.Image) -> float:
    """Locate the opaque upper body, above the sword and walking feet."""
    alpha = frame.getchannel("A")
    weighted_x = 0
    pixel_count = 0
    for y in range(30, 80):
        for x in range(SOURCE_FRAME_SIZE[0]):
            if alpha.getpixel((x, y)) > 20:
                weighted_x += x
                pixel_count += 1
    assert pixel_count > 0, "A master walk frame has no upper body"
    return weighted_x / pixel_count


def main() -> None:
    start_frames = parse_flattened_aseprite(SOURCE / "walk-start.aseprite")
    assert len(start_frames) == 11
    assert all(frame.size == SOURCE_FRAME_SIZE for frame in start_frames)

    loop_source = Image.open(SOURCE / "walking-sheet.png").convert("RGBA")
    assert loop_source.size == (512, 1280)
    loop_frames = [
        loop_source.crop((
            index % 2 * 256,
            index // 2 * 256,
            (index % 2 + 1) * 256,
            (index // 2 + 1) * 256,
        ))
        for index in range(LOOP_FRAME_COUNT)
    ]

    # A 320px canvas gives the full sword room while retaining the same world
    # position for the head and feet across the start-to-loop seam.
    target_head_x = head_center_x(start_frames[-1]) + 32.0
    ground_y = start_frames[-1].getbbox()[3]
    normalized_frames: list[Image.Image] = []
    for source in loop_frames:
        source_box = source.getbbox()
        assert source_box is not None
        offset_x = round(target_head_x - head_center_x(source))
        offset_y = ground_y - source_box[3]
        assert source_box[0] + offset_x >= 0
        assert source_box[2] + offset_x <= LOOP_FRAME_SIZE[0]
        assert source_box[1] + offset_y >= 0
        assert source_box[3] + offset_y <= LOOP_FRAME_SIZE[1]
        frame = Image.new("RGBA", LOOP_FRAME_SIZE)
        frame.alpha_composite(source, (offset_x, offset_y))
        normalized_frames.append(frame)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    save_sheet(start_frames, START_OUTPUT, 4)
    save_sheet(normalized_frames, LOOP_OUTPUT, 4)
    print(f"Exported {len(start_frames)} start frames and {len(normalized_frames)} walk frames")


if __name__ == "__main__":
    main()

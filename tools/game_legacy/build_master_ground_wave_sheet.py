"""Export the phase-two uppercut's ground wave animation."""

from pathlib import Path

from build_master_clean_sheets import parse_flattened_aseprite, save_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/最终成品/二阶段/上挑/dibo.aseprite"
OUTPUT = ROOT / "assets/sideview/effects/master_wind/phase2/uppercut_ground_wave_266x116_4f.png"
FRAME_SIZE = (266, 116)
FRAME_COUNT = 4


def main() -> None:
    frames = parse_flattened_aseprite(SOURCE)
    assert len(frames) == FRAME_COUNT, f"Unexpected ground wave frame count: {len(frames)}"
    assert all(frame.size == FRAME_SIZE for frame in frames), "Unexpected ground wave canvas size"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    save_sheet(frames, OUTPUT, FRAME_COUNT)


if __name__ == "__main__":
    main()

from pathlib import Path

from build_master_clean_sheets import parse_flattened_aseprite, save_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/主角-岚/手动作业区"
BODY_OUTPUT = ROOT / "assets/sideview/characters/lan/parry/gedang_plus_192x64_6f.png"
FX_OUTPUT = ROOT / "assets/sideview/effects/lan_parry/gedang_plus_fx_300x300_2f.png"


def build_sheet(source_name: str, output: Path, frame_size: tuple[int, int], count: int) -> None:
    frames = parse_flattened_aseprite(SOURCE / source_name)
    assert len(frames) == count, f"Unexpected frame count in {source_name}"
    assert all(frame.size == frame_size for frame in frames), f"Unexpected canvas in {source_name}"
    output.parent.mkdir(parents=True, exist_ok=True)
    save_sheet(frames, output, count)


if __name__ == "__main__":
    build_sheet("gedang-plus.aseprite", BODY_OUTPUT, (192, 64), 6)
    build_sheet("gedang-plus-fx.aseprite", FX_OUTPUT, (300, 300), 2)

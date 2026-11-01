"""Remove the 10 retired bank-dive frames, preserving all 15 live frames exactly.

The old combined sheet is archived with tools/restructure/move_res_paths.py after
this tool runs. This is deterministic sprite packing, with no painted changes.
"""
from pathlib import Path
import hashlib
import json

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / "homeing-star-game"
ARCHIVE = ROOT / "homeing-star-temp-assert/Archive/game-unused-20261019/lan_bank_dive_20261031"
RELATIVE = Path("assets/characters/lan/body/swim")
OLD_NAME = "enter_160x160_25f.png"
NEW_NAME = "enter_160x160_15f.png"


def main():
    original = GAME / RELATIVE / OLD_NAME
    if not original.exists():
        original = ARCHIVE / RELATIVE / OLD_NAME
    target = GAME / RELATIVE / NEW_NAME
    with Image.open(original) as image:
        image.load()
        assert image.size == (4000, 160)
        retained = image.crop((1600, 0, 4000, 160))
        if target.exists():
            with Image.open(target) as existing:
                assert existing.mode == retained.mode and existing.tobytes() == retained.tobytes()
        else:
            retained.save(target)
        with Image.open(target) as result:
            assert result.size == (2400, 160)
            for frame in range(15):
                source_frame = image.crop(((frame + 10) * 160, 0, (frame + 11) * 160, 160))
                runtime_frame = result.crop((frame * 160, 0, (frame + 1) * 160, 160))
                assert source_frame.tobytes() == runtime_frame.tobytes(), frame
    report = {
        "retired_source_frames": list(range(10)),
        "preserved_source_frames": list(range(10, 25)),
        "runtime_frames": list(range(15)),
        "all_preserved_frames_pixel_identical": True,
        "source_sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
        "runtime_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "runtime_size": [2400, 160],
        "original_archive": str(ARCHIVE / RELATIVE / OLD_NAME),
    }
    out = ROOT / "homeing-star-test/artifacts/lan_bank_dive_cleanup_20261031"
    out.mkdir(parents=True, exist_ok=True)
    (out / "frame_verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()

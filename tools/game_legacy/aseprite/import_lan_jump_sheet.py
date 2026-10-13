"""Import Lan's hand-edited jump sheet into the runtime asset directory."""

from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "PendingArt"
    / "character"
    / "主角-岚"
    / "palette-bases"
    / "jump"
    / "sprite sheets"
    / "jump.png"
)
TARGET = ROOT / "assets" / "sideview" / "characters" / "lan" / "jump" / "jump.png"
EXPECTED_SIZE = (256, 480)


def main() -> None:
    image = Image.open(SOURCE)
    if image.size != EXPECTED_SIZE or image.mode != "RGBA":
        raise ValueError(f"{SOURCE} must be a {EXPECTED_SIZE} RGBA image")

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, TARGET)
    print(f"Imported {TARGET.relative_to(ROOT)}: 24 frames of 64x80")


if __name__ == "__main__":
    main()

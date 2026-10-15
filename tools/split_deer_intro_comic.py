"""Losslessly split the approved M09 page, removing only frame ink and gutters."""
import json
from pathlib import Path
from PIL import Image

WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE = WORKSPACE / "homeing-star-temp-assert/PendingArt/m09_deer_encounter/20261015-v01"
DEST = WORKSPACE / "homeing-star-game/assets/ui/comics/deer_intro"
PANELS = [
    ("01_blocked_path.png", (14, 11, 1010, 386)),
    ("02_unease.png", (14, 405, 489, 749)),
    ("03_white_chest.png", (508, 405, 1010, 749)),
    ("04_hostility.png", (14, 767, 486, 1104)),
    ("05_sword_guard.png", (505, 767, 1010, 1104)),
    ("06_confrontation.png", (14, 1124, 1010, 1521)),
]


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = []
    with Image.open(SOURCE / "page-01.png") as page:
        if page.size != (1024, 1536):
            raise ValueError(f"Unexpected source size: {page.size}")
        for filename, box in PANELS:
            frame = page.crop(box)
            frame.save(DEST / filename)
            manifest.append({"file": filename, "source": "page-01.png", "box": box, "size": frame.size})
    (SOURCE / "panel-crops.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(manifest)} lossless M09 panels to {DEST}")


if __name__ == "__main__":
    main()

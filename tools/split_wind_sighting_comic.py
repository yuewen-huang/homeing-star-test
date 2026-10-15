"""Losslessly crop the approved M07 v03 page; keep its exact artwork and proportions."""
import json
from pathlib import Path
from PIL import Image

WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE = WORKSPACE / "homeing-star-temp-assert/PendingArt/m07_distant_back/20261015-v03-acting"
DEST = WORKSPACE / "homeing-star-game/assets/ui/comics/wind_sighting"
PANELS = [
    ("01_distant_back.png", (13, 9, 1011, 389)),
    ("02_recognition.png", (13, 407, 498, 721)),
    ("03_backpack_glimmer.png", (518, 407, 1011, 721)),
    ("04_calling.png", (13, 741, 618, 1092)),
    ("05_losing_sight.png", (639, 741, 1011, 1092)),
    ("06_empty_branches.png", (13, 1113, 1011, 1523)),
]


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = []
    with Image.open(SOURCE / "page-01.png") as page:
        if page.size != (1024, 1536):
            raise ValueError(f"Unexpected M07 source size: {page.size}")
        for filename, box in PANELS:
            frame = page.crop(box)
            frame.save(DEST / filename)
            manifest.append({"file": filename, "source": "page-01.png", "box": box, "size": frame.size})
    (SOURCE / "panel-crops.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(manifest)} lossless M07 frames to {DEST}")


if __name__ == "__main__":
    main()

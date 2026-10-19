"""Losslessly split the approved two comic pages into six runtime PNGs."""
import json
from pathlib import Path
from PIL import Image

WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE = WORKSPACE / "homeing-star-temp-assert/PendingArt/town_to_mist_forest_comic/20261015-v01"
DEST = WORKSPACE / "homeing-star-game/assets/shared/ui/comics/forest_entry"
# Pillow boxes: left, top, right, bottom (right/bottom excluded).
# Remove only page borders/gutters; never resize or stretch the artwork.
PANELS = [
    ("01_farewell.png", "page-01.png", (12, 8, 570, 808)),
    ("02_town_street.png", "page-01.png", (592, 8, 1014, 808)),
    ("03_town_gate.png", "page-01.png", (12, 830, 1014, 1525)),
    ("04_forest_path.png", "page-02.png", (14, 9, 1013, 464)),
    ("05_lan_notices.png", "page-02.png", (14, 482, 297, 1525)),
    ("06_yupo_searching.png", "page-02.png", (315, 482, 1013, 1525)),
]

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = []
    for filename, source, box in PANELS:
        with Image.open(SOURCE / source) as page:
            if page.size != (1024, 1536):
                raise ValueError(f"Unexpected source size: {source}: {page.size}")
            frame = page.crop(box)
            frame.save(DEST / filename)
            manifest.append({"file": filename, "source": source, "box": box, "size": frame.size})
    (SOURCE / "panel-crops.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(manifest)} lossless frames to {DEST}")

if __name__ == "__main__":
    main()

"""Reproduce the four approved wordless aftermath panels without resampling."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "homeing-star-temp-assert/PendingArt/deer_aftermath/20261109"
OUTPUT = ROOT / "homeing-star-game/assets/shared/ui/comics/deer_aftermath"
PANELS = [
    ("01_bound_exit.png", "page.png", (9, 9, 1016, 376)),
    ("02_roots_released.png", "page.png", (9, 391, 1016, 760)),
    ("03_dark_current.png", "page.png", (9, 775, 1016, 1120)),
    # User chose the earlier natural pose over the exaggerated head-turn edit.
    ("04_departure.png", "page_initial.png", (9, 1135, 1016, 1527)),
]

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, source, box in PANELS:
        image = Image.open(SOURCE / source)
        assert image.size == (1024, 1536), image.size
        frame = image.crop(box)
        frame.save(OUTPUT / name)
        manifest.append({"source": source, "file": name, "box": box, "size": frame.size})
    (SOURCE / "panel-crops.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Exported", len(PANELS), "unaltered panels")

if __name__ == "__main__":
    main()

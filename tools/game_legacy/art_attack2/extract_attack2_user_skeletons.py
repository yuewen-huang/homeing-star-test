from pathlib import Path
from PIL import Image

SRC = Path(r"D:\Temp\codex-clipboard-89486242-8809-4927-8424-160831a01d69.png")
OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1\user-skeletons")

def main():
    im = Image.open(SRC).convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    # Screenshot panels are displayed at 2x the 192px working-cell width.
    crops = {
        "ab-inbetween-1.png": (390, 0, 768, 376),
        "ab-inbetween-2.png": (778, 0, 1151, 376),
    }
    for name, box in crops.items():
        panel = im.crop(box).resize((192, 192), Image.Resampling.LANCZOS)
        panel.save(OUT / name)

if __name__ == "__main__":
    main()

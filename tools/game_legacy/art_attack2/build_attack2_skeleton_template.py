from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT = ROOT / "skeleton-template.png"
W, H, LABEL_H = 192, 192, 28
SLOTS = 13
ANCHORS = {0: ("A", "1.png"), 4: ("B", "3.png"), 8: ("C", "5.png"), 12: ("D", "8.png")}


def main():
    sheet = Image.new("RGBA", (W * SLOTS, H + LABEL_H), (255, 255, 255, 255))
    draw = ImageDraw.Draw(sheet, "RGBA")
    for i in range(SLOTS):
        x = i * W
        draw.rectangle((x, 0, x + W - 1, H - 1), outline=(170, 176, 184, 150), width=1)
        draw.line((x + 8, 176, x + W - 8, 176), fill=(120, 126, 136, 100), width=1)
        if i in ANCHORS:
            tag, name = ANCHORS[i]
            frame = Image.open(ROOT / name).convert("RGBA")
            frame.putalpha(frame.getchannel("A").point(lambda a: round(a * 0.30)))
            sheet.alpha_composite(frame, (x, 0))
            draw.text((x + 8, H + 7), f"{tag}  LOCKED SOURCE", fill=(30, 34, 40, 255))
        else:
            draw.text((x + 8, H + 7), "DRAW SKELETON HERE", fill=(115, 120, 128, 255))
    sheet.save(OUT)


if __name__ == "__main__":
    main()

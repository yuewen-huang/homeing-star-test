from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(r"D:\homing-star-godot\PendingArt\character\师傅\参考\Elementals_fire_knight_FREE_v1.1\png\fire_knight\05_1_atk")
OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\视频抽帧版本\攻击1\分析")

OUT.mkdir(parents=True, exist_ok=True)
scale = 4
cell_w, cell_h = 288 * scale, 128 * scale
sheet = Image.new("RGBA", (cell_w * 2, cell_h * 6), (18, 18, 20, 255))
for i in range(1, 12):
    frame = Image.open(SRC / f"1_atk_{i}.png").convert("RGBA")
    enlarged = frame.resize((cell_w, cell_h), Image.Resampling.NEAREST)
    d = ImageDraw.Draw(enlarged)
    d.text((12, 10), f"REFERENCE {i:02d}", fill=(255,255,255,255), stroke_width=2, stroke_fill=(0,0,0,255))
    x, y = ((i-1) % 2) * cell_w, ((i-1) // 2) * cell_h
    sheet.alpha_composite(enlarged, (x, y))
sheet.save(OUT / "attack1-reference-4x.png")

# Dedicated high-magnification crops for leg tracing in frames 02-08.
leg_sheet = Image.new("RGBA", (128 * 8, 7 * 56 * 8), (18, 18, 20, 255))
for row, i in enumerate(range(2, 9)):
    frame = Image.open(SRC / f"1_atk_{i}.png").convert("RGBA")
    crop = frame.crop((96, 72, 224, 128)).resize((128 * 8, 56 * 8), Image.Resampling.NEAREST)
    d = ImageDraw.Draw(crop)
    d.text((8, 6), f"LEGS REFERENCE {i:02d}", fill=(255,255,255,255), stroke_width=2, stroke_fill=(0,0,0,255))
    leg_sheet.alpha_composite(crop, (0, row * 56 * 8))
leg_sheet.save(OUT / "attack1-legs-02-08-8x.png")
print(OUT / "attack1-reference-4x.png")

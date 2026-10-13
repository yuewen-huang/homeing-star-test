from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SRC = Path(r"D:\homing-star-godot\PendingArt\character\师傅\旧版全部废弃\视频抽帧版本\待机\角色母版\师傅-一阶段-像素母版-320x192-30色-v1.png")
OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\PixelOver工程\拆件")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")
    mask = Image.new("L", src.size, 0)
    d = ImageDraw.Draw(mask)

    # Visible blade: tight polygon following both blade edges.
    d.polygon([
        (48, 179), (48, 184), (55, 184), (159, 119),
        (163, 116), (158, 109), (153, 107), (145, 113)
    ], fill=255)
    # Cross guard. The hand pixels above it remain outside this mask.
    d.polygon([
        (151, 100), (156, 98), (176, 116), (172, 122),
        (166, 118), (168, 114), (153, 106), (150, 108)
    ], fill=255)
    # Visible grip/pommel fragments between and behind the hands.
    d.polygon([(157, 101), (162, 97), (181, 105), (179, 112), (166, 109)], fill=255)

    source_alpha = src.getchannel("A")
    weapon_alpha = Image.fromarray(np.minimum(np.asarray(mask), np.asarray(source_alpha)).astype(np.uint8), "L")
    weapon = src.copy(); weapon.putalpha(weapon_alpha)

    remainder_alpha = np.asarray(source_alpha).copy()
    remainder_alpha[np.asarray(mask) > 0] = 0
    remainder = src.copy(); remainder.putalpha(Image.fromarray(remainder_alpha.astype(np.uint8), "L"))

    weapon.save(OUT / "01_PROP_巨剑_可见部分_待修边.png")
    remainder.save(OUT / "02_BODY_去剑角色_待补底.png")
    src.save(OUT / "00_REF_完整母版_锁定.png")

    # 3x nearest-neighbour inspection sheet: original / weapon / remainder.
    checker = Image.new("RGBA", src.size, (210, 214, 218, 255))
    cd = ImageDraw.Draw(checker)
    for y in range(0, src.height, 16):
        for x in range(0, src.width, 16):
            if ((x // 16) + (y // 16)) % 2:
                cd.rectangle((x, y, x + 15, y + 15), fill=(168, 174, 180, 255))
    sheet = Image.new("RGBA", (src.width * 3, src.height), (0, 0, 0, 0))
    for i, layer in enumerate((src, weapon, remainder)):
        panel = checker.copy(); panel.alpha_composite(layer)
        sheet.alpha_composite(panel, (i * src.width, 0))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST)
    sheet.save(OUT / "切分检查_原图-巨剑-去剑角色.png")
    print(OUT)


if __name__ == "__main__":
    main()

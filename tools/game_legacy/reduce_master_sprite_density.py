from pathlib import Path
from collections import Counter

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(r"D:\homing-star-godot\PendingArt\character\师傅\旧版全部废弃\视频抽帧版本\待机\角色母版\师傅-一阶段-像素母版-320x192-30色-v1.png")
HERO = Path(r"D:\homing-star-godot\assets\sideview\characters\lan\idle.png")
OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\像素母版-v2")


def visible_bbox(im: Image.Image):
    a = np.asarray(im.getchannel("A"))
    y, x = np.nonzero(a)
    return (int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")
    crop = src.crop(visible_bbox(src))
    target_h = 100
    target_w = round(crop.width * target_h / crop.height)
    # BOX performs an actual information reduction before the hard pixel grid.
    small = crop.resize((target_w, target_h), Image.Resampling.BOX)
    alpha = small.getchannel("A").point(lambda v: 255 if v >= 96 else 0)
    rgb = Image.new("RGB", small.size, (18, 20, 21))
    rgb.paste(small.convert("RGB"), mask=alpha)
    target_colors = 16
    # Collapse high-frequency material texture before palette reduction. This is
    # intentionally aggressive: coat stitching, trouser quilting and blade
    # scratches are not gameplay-readable at the target scale.
    simplified_rgb = rgb.filter(ImageFilter.MedianFilter(size=3))
    q = simplified_rgb.quantize(colors=target_colors, method=Image.Quantize.MEDIANCUT,
                                dither=Image.Dither.NONE)
    palette = q.getpalette()

    # Remove only isolated interior color noise. Silhouette pixels and facial
    # edge pixels are untouched because they do not have four opaque neighbors.
    idx = np.asarray(q).copy()
    opaque = np.asarray(alpha) > 0
    for _ in range(3):
        nxt = idx.copy()
        for y in range(1, idx.shape[0] - 1):
            for x in range(1, idx.shape[1] - 1):
                if not opaque[y, x] or not (opaque[y-1, x] and opaque[y+1, x] and opaque[y, x-1] and opaque[y, x+1]):
                    continue
                neighbors = [idx[y-1, x], idx[y+1, x], idx[y, x-1], idx[y, x+1]]
                color, count = Counter(neighbors).most_common(1)[0]
                if count >= 3 and color != idx[y, x]:
                    nxt[y, x] = color
        idx = nxt
    q = Image.fromarray(idx.astype(np.uint8), "P")
    q.putpalette(palette)
    reduced = q.convert("RGBA")
    reduced.putalpha(alpha)

    canvas = Image.new("RGBA", (192, 128), (0, 0, 0, 0))
    canvas.alpha_composite(reduced, ((192 - target_w) // 2, 124 - target_h))
    out_file = OUT / "师傅-一阶段-巨剑母版-192x128-角色高100-16色-v3.png"
    canvas.save(out_file)

    # Same-baseline comparison at native pixel scale.
    hero_sheet = Image.open(HERO).convert("RGBA")
    hero = hero_sheet.crop((0, 0, 46, 55))
    preview = Image.new("RGBA", (300, 144), (32, 37, 42, 255))
    baseline = 130
    preview.alpha_composite(hero, (38, baseline - 55))
    preview.alpha_composite(canvas, (100, baseline - 124))
    d = ImageDraw.Draw(preview)
    d.line((0, baseline, 300, baseline), fill=(100, 112, 122, 255), width=1)
    d.text((34, 8), "LAN 46x55", fill=(220, 224, 228, 255))
    d.text((156, 8), "MASTER ~100px", fill=(220, 224, 228, 255))
    preview = preview.resize((900, 432), Image.Resampling.NEAREST)
    preview.save(OUT / "主角与师傅-原生像素比例对比-v3.png")

    arr = np.asarray(canvas)
    vis = arr[..., 3] > 0
    colors = len(np.unique(arr[vis, :3], axis=0))
    print(f"output={out_file}")
    print(f"source_bbox={visible_bbox(src)} reduced={target_w}x{target_h} visible_colors={colors}")


if __name__ == "__main__":
    main()

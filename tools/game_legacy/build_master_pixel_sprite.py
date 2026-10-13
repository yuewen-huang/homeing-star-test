from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def edge_background_mask(rgb: np.ndarray, bg_min: int = 168) -> np.ndarray:
    """Flood only pale neutral pixels connected to the canvas edge."""
    hi = rgb.max(axis=2).astype(np.int16)
    lo = rgb.min(axis=2).astype(np.int16)
    eligible = (lo >= bg_min) & ((hi - lo) <= 28)
    h, w = eligible.shape
    seen = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        if eligible[0, x]:
            seen[0, x] = True
            queue.append((0, x))
        if eligible[h - 1, x]:
            seen[h - 1, x] = True
            queue.append((h - 1, x))
    for y in range(h):
        if eligible[y, 0] and not seen[y, 0]:
            seen[y, 0] = True
            queue.append((y, 0))
        if eligible[y, w - 1] and not seen[y, w - 1]:
            seen[y, w - 1] = True
            queue.append((y, w - 1))

    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and eligible[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def largest_component(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros_like(mask)
    largest: list[tuple[int, int]] = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        queue = deque([(y, x)])
        component: list[tuple[int, int]] = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    out = np.zeros_like(mask)
    if largest:
        yy, xx = zip(*largest)
        out[np.asarray(yy), np.asarray(xx)] = True
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=192)
    parser.add_argument("--colors", type=int, default=30)
    parser.add_argument("--palette-source")
    parser.add_argument("--bg-min", type=int, default=168)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    # Work at half resolution: it removes generated pseudo-pixel micro-noise while
    # keeping the authored silhouette and all gameplay-readable features.
    work = source.resize((source.width // 2, source.height // 2), Image.Resampling.NEAREST)
    rgb = np.asarray(work)
    foreground = largest_component(~edge_background_mask(rgb, args.bg_min))

    ys, xs = np.nonzero(foreground)
    if len(xs) == 0:
        raise RuntimeError("No foreground component detected")
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    rgba = work.convert("RGBA")
    alpha = Image.fromarray((foreground * 255).astype(np.uint8), "L")
    rgba.putalpha(alpha)
    rgba = rgba.crop(box)

    max_w, max_h = args.width - 8, args.height - 8
    scale = min(max_w / rgba.width, max_h / rgba.height)
    size = (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale)))
    rgba = rgba.resize(size, Image.Resampling.NEAREST)

    # Quantize the visible sprite without dithering; restore the hard alpha mask.
    alpha = rgba.getchannel("A")
    flattened = Image.new("RGB", rgba.size, (19, 22, 23))
    flattened.paste(rgba.convert("RGB"), mask=alpha)
    if args.palette_source:
        palette_rgba = np.asarray(Image.open(args.palette_source).convert("RGBA"))
        visible = palette_rgba[..., 3] > 0
        palette_colors = np.unique(palette_rgba[visible, :3], axis=0)[:args.colors]
        palette_data = palette_colors.flatten().tolist()
        filler = palette_colors[0].tolist()
        while len(palette_data) < 768:
            palette_data.extend(filler)
        palette_image = Image.new("P", (1, 1))
        palette_image.putpalette(palette_data)
        quantized = flattened.quantize(palette=palette_image, dither=Image.Dither.NONE).convert("RGBA")
    else:
        quantized = flattened.quantize(colors=args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    quantized.putalpha(alpha)

    canvas = Image.new("RGBA", (args.width, args.height), (0, 0, 0, 0))
    x = (args.width - quantized.width) // 2
    y = args.height - 4 - quantized.height
    canvas.alpha_composite(quantized, (x, y))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    opaque = np.asarray(canvas)[..., 3] > 0
    colors = np.unique(np.asarray(canvas)[opaque, :3], axis=0)
    print(f"saved={output}")
    print(f"source={source.size} crop={box} sprite={size} canvas={canvas.size}")
    print(f"opaque_colors={len(colors)} alpha_values={np.unique(np.asarray(canvas)[..., 3]).tolist()}")


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def component_mask(candidate: np.ndarray, seeds: np.ndarray) -> np.ndarray:
    h, w = candidate.shape
    seen = np.zeros_like(candidate, dtype=bool)
    q: deque[tuple[int, int]] = deque()
    best = np.zeros_like(candidate, dtype=bool)
    best_score = -1
    for start_y, start_x in zip(*np.nonzero(candidate)):
        if seen[start_y, start_x]:
            continue
        component: list[tuple[int, int]] = []
        seen[start_y, start_x] = True
        q.append((start_y, start_x))
        while q:
            y, x = q.popleft()
            component.append((y, x))
            for ny, nx in (
                (y - 1, x - 1), (y - 1, x), (y - 1, x + 1),
                (y, x - 1), (y, x + 1),
                (y + 1, x - 1), (y + 1, x), (y + 1, x + 1),
            ):
                if 0 <= ny < h and 0 <= nx < w and candidate[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        seed_count = sum(bool(seeds[y, x]) for y, x in component)
        score = seed_count * 20 + len(component)
        if score > best_score:
            best_score = score
            best.fill(False)
            for y, x in component:
                best[y, x] = True
    return best


def fill_holes(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    outside = np.zeros_like(mask, dtype=bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                q.append((ny, nx))
    return mask | ~outside


def extract(slot: Image.Image) -> Image.Image:
    rgb = np.asarray(slot.convert("RGB"), dtype=np.int16)
    hi = rgb.max(axis=2)
    lo = rgb.min(axis=2)
    chroma = hi - lo
    # Strong colored/dark sprite pixels seed the extraction. Near-neutral checkerboard
    # and pale guide residue are excluded; connected silver sword pixels are retained.
    seeds = (chroma >= 22) | (hi <= 105)
    candidate = (chroma >= 12) | (hi <= 140)
    mask = fill_holes(component_mask(candidate, seeds))
    mask_img = Image.fromarray((mask * 255).astype(np.uint8), "L")
    mask_img = mask_img.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    rgba = slot.convert("RGBA")
    rgba.putalpha(mask_img)
    bbox = mask_img.getbbox()
    if bbox is None:
        raise RuntimeError("No foreground detected in slot")
    return rgba.crop(bbox)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--locked-dir", required=True)
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--lock-indices", default="1,4,8,12")
    args = ap.parse_args()

    raw = Image.open(args.input).convert("RGB")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    frame_count = args.frames
    lock_indices = [int(value) - 1 for value in args.lock_indices.split(",")]
    if len(lock_indices) != 4:
        raise ValueError("--lock-indices must contain four comma-separated positions")
    step = raw.width / frame_count
    extracted: list[Image.Image] = []
    for i in range(frame_count):
        left = round(i * step)
        right = round((i + 1) * step)
        extracted.append(extract(raw.crop((left, 0, right, raw.height))))

    locked_dir = Path(args.locked_dir)
    locked = [Image.open(locked_dir / f"{n}.png").convert("RGBA") for n in "abcd"]
    locked_boxes = [im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox() for im in locked]
    max_w = max([im.width for im in extracted] + [b[2] - b[0] for b in locked_boxes if b])
    max_h = max([im.height for im in extracted] + [b[3] - b[1] for b in locked_boxes if b])
    scale = min(168 / max_h, 160 / max_w)

    frames: list[Image.Image] = []
    for sprite in extracted:
        size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
        sprite = sprite.resize(size, Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
        frame.alpha_composite(sprite, ((192 - sprite.width) // 2, 176 - sprite.height))
        bbox = frame.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if bbox and bbox[3] - 1 != 175:
            aligned = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
            aligned.alpha_composite(frame, (0, 175 - (bbox[3] - 1)))
            frame = aligned
        frames.append(frame)

    # Absolute lockback: these files are copied pixel-for-pixel into final slots.
    for index, source in zip(lock_indices, locked):
        frames[index] = source.copy()
    for i, frame in enumerate(frames, 1):
        frame.save(out_dir / f"{i:02d}.png")


if __name__ == "__main__":
    main()

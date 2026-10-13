from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


DIRECTIONS = ((1, 0), (0, 1), (1, 1), (1, -1))


def line_support(mask: np.ndarray, y: int, x: int) -> bool:
    h, w = mask.shape
    for dx, dy in DIRECTIONS:
        forward = 0
        backward = 0
        for distance in range(1, 5):
            nx, ny = x + dx * distance, y + dy * distance
            if 0 <= nx < w and 0 <= ny < h and mask[ny, nx]:
                forward += 1
            else:
                break
        for distance in range(1, 5):
            nx, ny = x - dx * distance, y - dy * distance
            if 0 <= nx < w and 0 <= ny < h and mask[ny, nx]:
                backward += 1
            else:
                break
        if forward + backward >= 4 and (forward >= 1 or backward >= 1):
            return True
    return False


def remove_tiny_components(mask: np.ndarray, minimum: int = 4) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    result = mask.copy()
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        q: deque[tuple[int, int]] = deque([(sy, sx)])
        seen[sy, sx] = True
        points: list[tuple[int, int]] = []
        while q:
            y, x = q.popleft()
            points.append((y, x))
            for ny in range(max(0, y - 1), min(h, y + 2)):
                for nx in range(max(0, x - 1), min(w, x + 2)):
                    if mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        if len(points) < minimum:
            for y, x in points:
                result[y, x] = False
    return result


def clean(image: Image.Image) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA")).copy()
    mask = rgba[:, :, 3] > 0
    padded = np.pad(mask, 1)
    neighbors = sum(
        padded[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
        for dy in range(3)
        for dx in range(3)
    ) - mask
    line_pixels = np.zeros_like(mask, dtype=bool)
    for y, x in zip(*np.nonzero(mask)):
        if line_support(mask, y, x):
            line_pixels[y, x] = True
    # Match the hand-cleaned reference: remove the noisy one-pixel outer shell,
    # while retaining pixels supported by at least seven surrounding sprite pixels.
    mask &= (neighbors >= 7) | line_pixels
    mask = remove_tiny_components(mask)
    rgba[:, :, 3] = np.where(mask, 255, 0).astype(np.uint8)
    rgba[~mask, :3] = 0
    return Image.fromarray(rgba, "RGBA")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", required=True)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--preserve", nargs="*", default=[])
    args = ap.parse_args()
    src = Path(args.input_dir)
    dst = Path(args.output_dir)
    dst.mkdir(parents=True, exist_ok=True)
    preserve = set(args.preserve)
    for path in sorted(src.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        output = image.copy() if path.stem in preserve else clean(image)
        output.save(dst / path.name)


if __name__ == "__main__":
    main()

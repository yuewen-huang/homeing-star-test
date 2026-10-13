from __future__ import annotations

import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

SOURCE = Path("PendingArt/character/师傅/BOSS形态/采用/冲刺/ChatGPT Image 2026年9月11日 17_45_01.png")
OUTPUT_DIR = SOURCE.parent / "dash-frames-aligned-v1"
COLS, ROWS = 4, 4
FRAME_SIZE = (512, 384)
ANCHOR = (256, 336)
ALPHA_THRESHOLD = 8


def edges(length: int, count: int) -> list[int]:
    return [round(i * length / count) for i in range(count + 1)]


def components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """Return 8-connected components as (y, x) pixel lists."""
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x_value in np.flatnonzero(mask[y] & ~seen[y]):
            x = int(x_value)
            if seen[y, x]:
                continue
            queue = deque([(y, x)])
            seen[y, x] = True
            pixels: list[tuple[int, int]] = []
            while queue:
                cy, cx = queue.popleft()
                pixels.append((cy, cx))
                for ny in range(max(0, cy - 1), min(height, cy + 2)):
                    for nx in range(max(0, cx - 1), min(width, cx + 2)):
                        if mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            queue.append((ny, nx))
            found.append(pixels)
    return found


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    pixels = np.array(source)
    x_edges = edges(source.width, COLS)
    y_edges = edges(source.height, ROWS)
    centers = [(x_edges[i] + x_edges[i + 1]) / 2 for i in range(COLS)]
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    records: list[dict] = []
    for row in range(ROWS):
        top, bottom = y_edges[row], y_edges[row + 1]
        row_mask = pixels[top:bottom, :, 3] > ALPHA_THRESHOLD
        groups = components(row_mask)

        assignments: list[list[tuple[int, int]]] = [[] for _ in range(COLS)]
        for group in groups:
            mean_x = sum(point[1] for point in group) / len(group)
            column = min(range(COLS), key=lambda i: abs(mean_x - centers[i]))
            assignments[column].extend(group)

        for column in range(COLS):
            group = assignments[column]
            if not group:
                raise RuntimeError(f"No pixels found for row {row + 1}, column {column + 1}")

            ys = np.fromiter((point[0] for point in group), dtype=np.int32)
            xs = np.fromiter((point[1] for point in group), dtype=np.int32)
            # Ignore isolated one-pixel generation debris when choosing the baseline.
            useful = np.zeros_like(row_mask)
            useful[ys, xs] = True
            row_counts = useful.sum(axis=1)
            baseline_row = int(np.flatnonzero(row_counts >= 3)[-1])

            nominal_left = x_edges[column]
            nominal_center = centers[column]
            x_shift = round(ANCHOR[0] - (nominal_center - nominal_left))
            y_shift = ANCHOR[1] - baseline_row

            out = np.zeros((FRAME_SIZE[1], FRAME_SIZE[0], 4), dtype=np.uint8)
            src_y = ys + top
            dst_x = xs - nominal_left + x_shift
            dst_y = ys + y_shift
            valid = (
                (dst_x >= 0) & (dst_x < FRAME_SIZE[0])
                & (dst_y >= 0) & (dst_y < FRAME_SIZE[1])
            )
            out[dst_y[valid], dst_x[valid]] = pixels[src_y[valid], xs[valid]]
            frame = Image.fromarray(out, "RGBA")
            frame_number = row * COLS + column + 1
            filename = f"dash_{frame_number:02d}.png"
            frame.save(OUTPUT_DIR / filename)
            frames.append(frame)
            records.append({
                "frame": frame_number,
                "file": filename,
                "source_row": row + 1,
                "source_column": column + 1,
                "anchor": {"left": nominal_left, "top": top, "right": x_edges[column + 1], "bottom": bottom},
                "pixel_shift": {"x": x_shift - nominal_left, "y": y_shift - top},
            })

    sheet = Image.new("RGBA", (FRAME_SIZE[0] * COLS, FRAME_SIZE[1] * ROWS))
    for index, frame in enumerate(frames):
        sheet.paste(frame, ((index % COLS) * FRAME_SIZE[0], (index // COLS) * FRAME_SIZE[1]), frame)
    sheet.save(OUTPUT_DIR / "dash_aligned_sheet_4x4.png")
    anchor_data = dict(x=ANCHOR[0], y=ANCHOR[1], convention="bottom_center")
    metadata = dict(
        source=str(SOURCE),
        source_size=list(source.size),
        frame_size=list(FRAME_SIZE),
        anchor=anchor_data,
        frames=records,
    )
    (OUTPUT_DIR / "anchors.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()

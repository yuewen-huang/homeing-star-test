"""Prototype a reusable cat-ear/tail pass for Lan animation sheets.

The workflow is deliberately non-destructive: it writes separate repair,
tail, ear and merged sheets plus a review image and machine-readable report.
The first supported preset is the 22-frame ``normal hit`` palette base.
"""
from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
LAN = ROOT / "PendingArt" / "character" / "主角-岚"
BASES = LAN / "palette-bases"
DEFAULT_INPUT = BASES / "hurt" / "sprite sheets" / "normal hit.png"
DEFAULT_TEMPLATE = LAN / "hurt" / "sprite sheets" / "normal hit.png"
DEFAULT_OUTPUT = BASES / "workflow-output" / "normal-hit-cat-trial"

FRAME_W, FRAME_H, COLUMNS, FRAME_COUNT = 70, 60, 4, 22
HAIR_COLORS = {
    (254, 230, 165),
    (245, 196, 119),
    (218, 154, 81),
    (171, 112, 60),
}
BODY_COLORS = {
    (39, 72, 76),
    (25, 43, 48),
    (49, 91, 96),
    (32, 56, 61),
}
HORN_SOURCE_COLORS = {
    (77, 47, 30),
    (169, 110, 103),
    (81, 55, 63),
    (145, 88, 76),
}
ROTATIONS = (-24, -12, 0, 12, 24)


@dataclass
class Candidate:
    score: float
    template_index: int
    angle: int
    image: Image.Image
    tip: tuple[int, int]
    visible_pixels: int
    overlap_pixels: int
    clipped_pixels: int


def connected_components(points: set[tuple[int, int]]) -> list[set[tuple[int, int]]]:
    components: list[set[tuple[int, int]]] = []
    while points:
        start = points.pop()
        component = {start}
        queue = [start]
        while queue:
            x, y = queue.pop()
            for neighbor in (
                (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
                (x - 1, y - 1), (x + 1, y - 1),
                (x - 1, y + 1), (x + 1, y + 1),
            ):
                if neighbor in points:
                    points.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        components.append(component)
    return components


def alpha_components(image: Image.Image, minimum: int = 1) -> list[Image.Image]:
    points = {
        (x, y)
        for y in range(image.height)
        for x in range(image.width)
        if image.getpixel((x, y))[3]
    }
    pieces: list[tuple[int, int, Image.Image]] = []
    for component in connected_components(points):
        if len(component) < minimum:
            continue
        left = min(x for x, _ in component)
        top = min(y for _, y in component)
        right = max(x for x, _ in component) + 1
        bottom = max(y for _, y in component) + 1
        pieces.append((top, left, image.crop((left, top, right, bottom))))
    return [piece for _, _, piece in sorted(pieces)]


def crop_frames(sheet: Image.Image) -> list[Image.Image]:
    frames = []
    for index in range(FRAME_COUNT):
        left = (index % COLUMNS) * FRAME_W
        top = (index // COLUMNS) * FRAME_H
        frames.append(sheet.crop((left, top, left + FRAME_W, top + FRAME_H)))
    return frames


def hair_points(frame: Image.Image) -> list[tuple[int, int]]:
    return [
        (x, y)
        for y in range(frame.height)
        for x in range(frame.width)
        if frame.getpixel((x, y))[3] and frame.getpixel((x, y))[:3] in HAIR_COLORS
    ]


def locate_crown(frame: Image.Image) -> tuple[int, int, float]:
    points = hair_points(frame)
    if not points:
        alpha = [(x, y) for y in range(frame.height) for x in range(frame.width) if frame.getpixel((x, y))[3]]
        if not alpha:
            return FRAME_W // 2, 4, 0.0
        points = alpha
    xs = sorted(x for x, _ in points)
    focus_x = xs[min(len(xs) - 1, int(len(xs) * 0.72))]
    nearby = [(x, y) for x, y in points if abs(x - focus_x) <= 6]
    crown_y = min(y for _, y in nearby)
    crown_band = [(x, y) for x, y in nearby if y <= crown_y + 3]
    crown_x = round(sum(x for x, _ in crown_band) / len(crown_band))
    confidence = min(1.0, len(points) / 120.0) * min(1.0, len(crown_band) / 8.0)
    return crown_x, crown_y, confidence


def nearest_hair_color(frame: Image.Image, x: int, y: int) -> tuple[int, int, int, int]:
    best: tuple[int, tuple[int, int, int, int]] | None = None
    for radius in range(1, 9):
        for yy in range(max(0, y - radius), min(frame.height, y + radius + 1)):
            for xx in range(max(0, x - radius), min(frame.width, x + radius + 1)):
                pixel = frame.getpixel((xx, yy))
                if pixel[3] and pixel[:3] in HAIR_COLORS:
                    distance = abs(xx - x) + abs(yy - y)
                    if best is None or distance < best[0]:
                        best = (distance, pixel)
        if best is not None:
            return best[1]
    return (254, 230, 165, 255)


def repair_horns(base: Image.Image, template: Image.Image, crown: tuple[int, int]) -> tuple[Image.Image, Image.Image, int]:
    result = base.copy()
    layer = Image.new("RGBA", base.size)
    cx, cy = crown
    candidates = {
        (x, y)
        for y in range(max(0, cy - 8), min(base.height, cy + 18))
        for x in range(max(0, cx - 20), min(base.width, cx + 18))
        if template.getpixel((x, y))[3]
        and template.getpixel((x, y))[:3] in HORN_SOURCE_COLORS
    }
    changed = 0
    for component in connected_components(candidates):
        if len(component) < 2:
            continue
        for x, y in component:
            color = nearest_hair_color(base, x, y)
            result.putpixel((x, y), color)
            layer.putpixel((x, y), color)
            changed += 1
    return result, layer, changed


def locate_tail_root(frame: Image.Image) -> tuple[int, int]:
    body = [
        (x, y)
        for y in range(frame.height)
        for x in range(frame.width)
        if frame.getpixel((x, y))[3] and frame.getpixel((x, y))[:3] in BODY_COLORS
    ]
    if not body:
        return FRAME_W // 2, FRAME_H // 2
    top = min(y for _, y in body)
    bottom = max(y for _, y in body)
    target_y = round(top + (bottom - top) * 0.72)
    band = [(x, y) for x, y in body if abs(y - target_y) <= 3]
    # Start inside the coat so the character layer naturally hides the root.
    return max(2, max(x for x, _ in band) - 9), target_y


def paste_tail_candidate(
    template: Image.Image,
    root: tuple[int, int],
    angle: int,
    body: Image.Image,
    previous_tip: tuple[int, int] | None,
    template_index: int,
) -> Candidate:
    rotated = template.rotate(angle, resample=Image.Resampling.NEAREST, expand=True)
    alpha = rotated.getchannel("A")
    bbox = alpha.getbbox()
    assert bbox is not None
    rotated = rotated.crop(bbox)
    # Tail templates point from their left endpoint toward the right.
    origin_y = rotated.height // 2
    left = root[0] - 1
    top = root[1] - origin_y
    layer = Image.new("RGBA", body.size)
    layer.alpha_composite(rotated, (left, top))
    source_pixels = sum(1 for value in rotated.getchannel("A").get_flattened_data() if value)
    placed_pixels = [(x, y) for y in range(layer.height) for x in range(layer.width) if layer.getpixel((x, y))[3]]
    clipped = source_pixels - len(placed_pixels)
    overlap = sum(1 for x, y in placed_pixels if body.getpixel((x, y))[3])
    visible = len(placed_pixels) - overlap
    tip = (min(FRAME_W - 1, left + rotated.width - 1), max(0, min(FRAME_H - 1, top + origin_y)))
    continuity = 0.0 if previous_tip is None else math.dist(tip, previous_tip)
    score = clipped * 30.0 + max(0, 18 - visible) * 4.0 + overlap * 0.35 + continuity * 1.8
    return Candidate(score, template_index, angle, layer, tip, visible, overlap, clipped)


def checker(frame: Image.Image, scale: int = 6) -> Image.Image:
    background = Image.new("RGBA", frame.size)
    draw = ImageDraw.Draw(background)
    for y in range(0, frame.height, 4):
        for x in range(0, frame.width, 4):
            shade = 92 if (x // 4 + y // 4) % 2 else 116
            draw.rectangle((x, y, x + 3, y + 3), fill=(shade, shade, shade, 255))
    background.alpha_composite(frame)
    return background.convert("RGB").resize((frame.width * scale, frame.height * scale), Image.Resampling.NEAREST)


def assemble_sheet(frames: list[Image.Image]) -> Image.Image:
    rows = math.ceil(FRAME_COUNT / COLUMNS)
    sheet = Image.new("RGBA", (FRAME_W * COLUMNS, FRAME_H * rows))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, ((index % COLUMNS) * FRAME_W, (index // COLUMNS) * FRAME_H))
    return sheet


def main() -> None:
    global FRAME_W, FRAME_H, COLUMNS, FRAME_COUNT
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--frame-width", type=int, default=FRAME_W)
    parser.add_argument("--frame-height", type=int, default=FRAME_H)
    parser.add_argument("--columns", type=int, default=COLUMNS)
    parser.add_argument("--frame-count", type=int, default=FRAME_COUNT)
    args = parser.parse_args()

    FRAME_W = args.frame_width
    FRAME_H = args.frame_height
    COLUMNS = args.columns
    FRAME_COUNT = args.frame_count

    args.output.mkdir(parents=True, exist_ok=True)
    base_frames = crop_frames(Image.open(args.input).convert("RGBA"))
    template_frames = crop_frames(Image.open(args.template).convert("RGBA"))
    ear_source = Image.open(BASES / "ear.png").convert("RGBA")
    ear_bbox = ear_source.getchannel("A").getbbox()
    if ear_bbox is None:
        raise ValueError("Ear template is empty")
    # Crop the supplied pair as one unit; their relative offset is intentional.
    ear_template = ear_source.crop(ear_bbox)
    tail_templates = alpha_components(Image.open(BASES / "weiba.png").convert("RGBA"), minimum=20)
    if len(tail_templates) != 4:
        raise ValueError(f"Expected four tail templates, found {len(tail_templates)}")

    repaired_frames: list[Image.Image] = []
    repair_layers: list[Image.Image] = []
    tail_layers: list[Image.Image] = []
    ear_layers: list[Image.Image] = []
    merged_frames: list[Image.Image] = []
    report: list[dict[str, object]] = []
    previous_tip: tuple[int, int] | None = None

    for index, (base, template) in enumerate(zip(base_frames, template_frames), 1):
        crown_x, crown_y, crown_confidence = locate_crown(base)
        repaired, repair_layer, repaired_pixels = repair_horns(base, template, (crown_x, crown_y))
        root = locate_tail_root(repaired)
        candidates = [
            paste_tail_candidate(tail, root, angle, repaired, previous_tip, tail_index)
            for tail_index, tail in enumerate(tail_templates)
            for angle in ROTATIONS
        ]
        chosen = min(candidates, key=lambda candidate: candidate.score)
        previous_tip = chosen.tip

        ears = Image.new("RGBA", base.size)
        ear_left = crown_x - 9
        ear_top = crown_y - 5
        ears.alpha_composite(ear_template, (ear_left, ear_top))

        merged = chosen.image.copy()
        merged.alpha_composite(repaired)
        merged.alpha_composite(ears)
        repaired_frames.append(repaired)
        repair_layers.append(repair_layer)
        tail_layers.append(chosen.image)
        ear_layers.append(ears)
        merged_frames.append(merged)
        low_confidence = crown_confidence < 0.45 or chosen.visible_pixels < 18 or chosen.clipped_pixels > 0 or repaired_pixels > 45
        report.append({
            "frame": index,
            "crown": [crown_x, crown_y],
            "crown_confidence": round(crown_confidence, 3),
            "repaired_horn_pixels": repaired_pixels,
            "tail_root": list(root),
            "tail_template": chosen.template_index + 1,
            "tail_angle": chosen.angle,
            "tail_visible_pixels": chosen.visible_pixels,
            "tail_overlap_pixels": chosen.overlap_pixels,
            "tail_clipped_pixels": chosen.clipped_pixels,
            "low_confidence": low_confidence,
        })

    outputs = {
        "character-repaired.png": repaired_frames,
        "layer-repair.png": repair_layers,
        "layer-tail-below.png": tail_layers,
        "layer-ears-above.png": ear_layers,
        "normal-hit-cat-merged.png": merged_frames,
    }
    for filename, frames in outputs.items():
        assemble_sheet(frames).save(args.output / filename)

    scale = 6
    review = Image.new("RGB", (COLUMNS * FRAME_W * scale, math.ceil(FRAME_COUNT / COLUMNS) * FRAME_H * scale), "#30323a")
    review_draw = ImageDraw.Draw(review)
    for index, frame in enumerate(merged_frames):
        x = (index % COLUMNS) * FRAME_W * scale
        y = (index // COLUMNS) * FRAME_H * scale
        review.paste(checker(frame, scale), (x, y))
        if report[index]["low_confidence"]:
            review_draw.rectangle((x, y, x + FRAME_W * scale - 1, y + FRAME_H * scale - 1), outline="#ff4058", width=4)
    review.save(args.output / "review-6x.png")
    gif_frames = [checker(frame, 4) for frame in merged_frames]
    gif_frames[0].save(
        args.output / "preview.gif",
        save_all=True,
        append_images=gif_frames[1:],
        duration=40,
        loop=0,
        disposal=2,
    )
    (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    low = sum(1 for row in report if row["low_confidence"])
    print(f"PASS: {FRAME_COUNT} frames written; low-confidence frames: {low}")


if __name__ == "__main__":
    main()

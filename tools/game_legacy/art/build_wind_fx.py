from __future__ import annotations

from math import cos, pi, sin
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "PendingArt" / "character" / "师傅" / "手工绑骨作业区" / "最终成品"
OUTPUT_ROOT = SOURCE_ROOT / "风魔法FX"
SHEETS = {
    "atak1-fx": (SOURCE_ROOT / "攻击" / "atak1-fx.png", 4, 3),
    "atak2-fx": (SOURCE_ROOT / "攻击" / "atak2-fx.png", 4, 5),
    "atak3-fx": (SOURCE_ROOT / "攻击" / "atak3-fx.png", 4, 7),
    "sp-atak-fx": (SOURCE_ROOT / "蓄力攻击" / "sp-atak-fx.png", 3, 6),
}

DEEP = (25, 105, 126, 255)
MID = (64, 174, 190, 255)
PALE = (155, 231, 226, 255)
WHITE = (232, 250, 239, 255)
SPECIAL_CONCEPT = OUTPUT_ROOT / "sp-atak-fx-wind-concept-v2.png"
_CONCEPT_FRAMES = None


def recolor_authored_arc(source: Image.Image) -> Image.Image:
    """Keep authored sword arcs whose silhouettes already read as wind."""
    rgba = np.asarray(source.convert("RGBA"), dtype=np.float32)
    rgb = rgba[..., :3] / 255.0
    luminance = rgb.max(axis=2)
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    energy = np.clip(0.68 * luminance + 0.32 * saturation, 0.0, 1.0)
    teal = np.array(DEEP[:3], dtype=np.float32)
    cyan = np.array(PALE[:3], dtype=np.float32)
    white = np.array(WHITE[:3], dtype=np.float32)
    low = np.clip(energy / 0.58, 0.0, 1.0)[..., None]
    high = np.clip((energy - 0.58) / 0.42, 0.0, 1.0)[..., None]
    wind_rgb = teal * (1.0 - low) + cyan * low
    wind_rgb = wind_rgb * (1.0 - high) + white * high
    out = np.zeros_like(rgba, dtype=np.uint8)
    out[..., :3] = np.clip(wind_rgb, 0, 255).astype(np.uint8)
    out[..., 3] = rgba[..., 3].astype(np.uint8)
    out[rgba[..., 3] == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


def bezier(p0, p1, p2, p3, steps=32):
    points = []
    for index in range(steps + 1):
        t = index / steps
        u = 1.0 - t
        points.append((
            round(u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]),
            round(u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]),
        ))
    return points


def draw_ribbon(draw: ImageDraw.ImageDraw, points, width: int) -> None:
    draw.line(points, fill=DEEP, width=width + 4, joint="curve")
    draw.line(points, fill=MID, width=width + 2, joint="curve")
    draw.line(points, fill=PALE, width=width, joint="curve")
    draw.line(points, fill=WHITE, width=max(1, width // 3), joint="curve")


def draw_forward_gust(frame: Image.Image, box, phase: float, strength: float = 1.0) -> None:
    draw = ImageDraw.Draw(frame)
    left, top, right, bottom = box
    width = max(20, right - left)
    height = max(16, bottom - top)
    center_y = (top + bottom) / 2
    line_width = max(2, round(3 * strength))
    for strand, y_factor in enumerate((-0.24, 0.0, 0.24)):
        y = center_y + y_factor * height
        bend = (0.16 + strand * 0.05) * height
        points = bezier(
            (left + width * 0.04, y + bend),
            (left + width * 0.32, y - bend),
            (left + width * 0.68, y + bend * (0.3 + phase)),
            (right - width * 0.03, y - bend * 0.4),
        )
        draw_ribbon(draw, points, line_width if strand == 1 else max(2, line_width - 1))
    for index in range(3):
        x = left + width * (0.18 + index * 0.25)
        y = top + height * (0.12 if index % 2 == 0 else 0.84)
        length = width * (0.11 + 0.03 * index)
        draw.line((x, y, x + length, y - height * 0.04), fill=PALE, width=max(1, line_width - 1))


def draw_vortex(frame: Image.Image, box, phase: float, dissolve: float = 0.0) -> None:
    draw = ImageDraw.Draw(frame)
    left, top, right, bottom = box
    cx = (left + right) / 2
    cy = (top + bottom) / 2
    width = max(24, right - left)
    height = max(24, bottom - top)
    turns = 5 if dissolve < 0.5 else 3
    for ring in range(turns):
        scale = 1.0 - ring * 0.15
        rx = width * 0.48 * scale
        ry = height * 0.45 * scale
        start = int(phase * 100 + ring * 52 + dissolve * 35)
        span = int(190 - dissolve * 65 - ring * 8)
        arc_box = (cx - rx, cy - ry, cx + rx, cy + ry)
        stroke = max(2, round((6 - ring) * (1.0 - dissolve * 0.45)))
        draw.arc(arc_box, start=start, end=start + span, fill=DEEP, width=stroke + 4)
        draw.arc(arc_box, start=start + 3, end=start + span - 7, fill=MID, width=stroke + 2)
        draw.arc(arc_box, start=start + 8, end=start + span - 15, fill=PALE, width=stroke)
        draw.arc(arc_box, start=start + 15, end=start + span - 28, fill=WHITE, width=max(1, stroke // 3))
    for index in range(6):
        angle = phase * 1.7 + index * pi / 3
        inner = 0.52 + dissolve * 0.12
        outer = 0.68 + index % 2 * 0.08
        x1 = cx + cos(angle) * width * inner
        y1 = cy + sin(angle) * height * inner
        x2 = cx + cos(angle) * width * outer
        y2 = cy + sin(angle) * height * outer
        draw.line((x1, y1, x2, y2), fill=PALE, width=2)


def load_concept_frames():
    global _CONCEPT_FRAMES
    if _CONCEPT_FRAMES is not None:
        return _CONCEPT_FRAMES
    concept = Image.open(SPECIAL_CONCEPT).convert("RGBA")
    source_w = concept.width // 3
    row_bands = ((0, 205), (205, 405), (405, 600), (600, 805), (805, concept.height))
    frames = []
    for row_top, row_bottom in row_bands:
        for col in range(3):
            frame = concept.crop((col * source_w, row_top, (col + 1) * source_w, row_bottom))
            rgba = np.asarray(frame).copy()
            rgba[rgba[..., 3] < 48] = 0
            frame = Image.fromarray(rgba, "RGBA")
            content_box = frame.getchannel("A").getbbox()
            if content_box is not None:
                frame = frame.crop(content_box)
            frames.append(frame)
    _CONCEPT_FRAMES = frames
    return frames


def weighted_centroid(image: Image.Image):
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[..., 3] / 255.0
    luminance = rgba[..., :3].max(axis=2) / 255.0
    weight = alpha * (0.2 + 0.8 * luminance)
    total = float(weight.sum())
    if total <= 0.0:
        return None
    yy, xx = np.indices(weight.shape)
    return float((xx * weight).sum() / total), float((yy * weight).sum() / total)


def fit_to_reference(artwork: Image.Image, reference: Image.Image, scale: float, align_core: bool) -> Image.Image:
    result = Image.new("RGBA", reference.size)
    target_box = reference.getchannel("A").getbbox()
    if target_box is None:
        return result
    target_w = max(1, round((target_box[2] - target_box[0]) * scale))
    target_h = max(1, round((target_box[3] - target_box[1]) * scale))
    fitted = artwork.copy()
    fitted.thumbnail((target_w, target_h), Image.Resampling.NEAREST)
    if align_core:
        reference_core = weighted_centroid(reference)
        artwork_core = weighted_centroid(fitted)
        x = round(reference_core[0] - artwork_core[0])
        y = round(reference_core[1] - artwork_core[1])
        x = min(max(0, x), reference.width - fitted.width)
        y = min(max(0, y), reference.height - fitted.height)
    else:
        x = target_box[0] + ((target_box[2] - target_box[0]) - fitted.width) // 2
        y = target_box[1] + ((target_box[3] - target_box[1]) - fitted.height) // 2
    result.alpha_composite(fitted, (x, y))
    return result


def build_frame(name: str, frame_index: int, source: Image.Image) -> Image.Image:
    box = source.getchannel("A").getbbox()
    if box is None:
        return Image.new("RGBA", source.size)
    if name != "sp-atak-fx" and not (name == "atak3-fx" and frame_index >= 20):
        return recolor_authored_arc(source)

    result = Image.new("RGBA", source.size)
    if name == "atak3-fx":
        artwork = load_concept_frames()[frame_index - 13]
        return fit_to_reference(artwork, source, 0.85, True)

    if frame_index <= 11:
        draw_forward_gust(result, box, frame_index * 0.11, 0.85 + frame_index * 0.025)
    else:
        draw_vortex(result, box, frame_index * 0.19, max(0.0, (frame_index - 14) / 3.0))
    return result


def build_special_from_concept(reference: Image.Image) -> Image.Image:
    """Fit the approved artwork into the exact authored frame bounds."""
    frame_w, frame_h = 576, 256
    result = Image.new("RGBA", (frame_w * 3, frame_h * 6))
    frames = load_concept_frames()

    # Runtime timing is inherited from the authored strip: frame 0 and frame
    # 17 are empty. Concept drawings occupy frames 1..15; frame 16 is the final
    # faded breakup. Every drawing is constrained to the original frame's
    # occupied rectangle, preserving size, center and ground-relative position.
    runtime_frames = [None, *frames]
    runtime_frames.extend((frames[-1].copy(), None))

    for index, artwork in enumerate(runtime_frames):
        if artwork is None:
            continue
        col = index % 3
        row = index // 3
        reference_frame = reference.crop((col * frame_w, row * frame_h, (col + 1) * frame_w, (row + 1) * frame_h))
        fitted = fit_to_reference(artwork, reference_frame, 0.5 if index >= 12 else 1.0, index >= 12)
        result.alpha_composite(fitted, (col * frame_w, row * frame_h))
    return result


def make_preview(sheet: Image.Image, columns: int, rows: int, output: Path) -> None:
    cell_w = sheet.width // columns
    cell_h = sheet.height // rows
    frames = []
    for index in range(columns * rows):
        col = index % columns
        row = index // columns
        frame = sheet.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
        if frame.getbbox() is not None:
            frames.append(frame)
    thumb_w, thumb_h, margin = 288, 128, 12
    preview_rows = (len(frames) + 3) // 4
    canvas = Image.new("RGBA", (thumb_w * 4 + margin * 5, thumb_h * preview_rows + margin * (preview_rows + 1)), (18, 26, 31, 255))
    draw = ImageDraw.Draw(canvas)
    for index, frame in enumerate(frames):
        frame.thumbnail((thumb_w - 16, thumb_h - 16), Image.Resampling.NEAREST)
        x = margin + (index % 4) * (thumb_w + margin) + (thumb_w - frame.width) // 2
        y = margin + (index // 4) * (thumb_h + margin) + (thumb_h - frame.height) // 2
        canvas.alpha_composite(frame, (x, y))
        draw.text((margin + (index % 4) * (thumb_w + margin) + 4, margin + (index // 4) * (thumb_h + margin) + 3), str(index + 1), fill=(128, 153, 158, 255))
    canvas.save(output)


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    report = []
    for name, (source_path, columns, rows) in SHEETS.items():
        source = Image.open(source_path).convert("RGBA")
        if source.width % columns or source.height % rows:
            raise ValueError(f"{source_path} does not divide into {columns}x{rows}")
        if name == "sp-atak-fx":
            result = build_special_from_concept(source)
        else:
            cell_w = source.width // columns
            cell_h = source.height // rows
            result = Image.new("RGBA", source.size)
            for frame_index in range(columns * rows):
                col = frame_index % columns
                row = frame_index // columns
                crop_box = (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
                result.alpha_composite(build_frame(name, frame_index, source.crop(crop_box)), (crop_box[0], crop_box[1]))
        output = OUTPUT_ROOT / f"{name}-wind.png"
        result.save(output)
        make_preview(result, columns, rows, OUTPUT_ROOT / f"{name}-wind-preview.png")
        report.append(f"{output.name}: {result.width}x{result.height}, grid={columns}x{rows}, geometry=wind-rebuilt")
    (OUTPUT_ROOT / "BUILD_REPORT.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))


if __name__ == "__main__":
    main()

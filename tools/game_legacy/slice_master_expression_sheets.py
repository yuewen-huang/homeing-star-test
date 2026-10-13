from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
EXPRESSIONS_ROOT = ROOT / "PendingArt" / "多情绪贴图"
OUTPUT_SIZE = (200, 300)
CONTENT_WIDTH = 180
CONTENT_TOP = 48


@dataclass(frozen=True)
class SheetSpec:
    source: Path
    output_dir: Path
    columns: int
    row_ranges: tuple[tuple[int, int], ...]
    names: tuple[str, ...]


SPECS = (
    SheetSpec(
        source=EXPRESSIONS_ROOT / "师傅一阶段" / "ChatGPT Image 2026年9月21日 17_49_06.png",
        output_dir=EXPRESSIONS_ROOT / "师傅一阶段" / "切图",
        columns=7,
        row_ranges=((66, 260), (306, 486), (534, 714), (762, 942)),
        names=(
            "通常", "微笑", "开怀", "喝酒", "微醺", "得意", "叹气",
            "惊讶", "疑惑", "思考", "认真", "无奈", "嫌弃", "摇头",
            "生气", "担忧", "疲惫", "欣励", "鼓励", "训诫", "大笑",
            "闭眼", "沉默", "严肃", "来吧", "再见", "调侃", "饮止",
        ),
    ),
    SheetSpec(
        source=EXPRESSIONS_ROOT / "师傅二阶段" / "ChatGPT Image 2026年9月21日 17_37_45.png",
        output_dir=EXPRESSIONS_ROOT / "师傅二阶段" / "切图",
        columns=10,
        row_ranges=((60, 215), (263, 420)),
        names=(
            "通常", "低吼", "怒视", "咆哮", "警觉", "疑惑", "不屑", "挑衅", "疲惫", "受伤",
            "愤怒", "狂暴", "冷静", "沉默", "失望", "悲伤", "无奈", "思考", "侧目", "闭眼",
        ),
    ),
)


def alpha_bbox(image: Image.Image, threshold: int = 8) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    return alpha.getbbox()


def slice_sheet(spec: SheetSpec) -> list[Path]:
    source = Image.open(spec.source).convert("RGBA")
    expected = spec.columns * len(spec.row_ranges)
    if len(spec.names) != expected:
        raise ValueError(f"{spec.source.name}: expected {expected} names, got {len(spec.names)}")

    spec.output_dir.mkdir(parents=True, exist_ok=True)
    slot_width = source.width / spec.columns
    shared_scale = CONTENT_WIDTH / slot_width
    outputs: list[Path] = []

    for index, name in enumerate(spec.names):
        row, column = divmod(index, spec.columns)
        left = round(column * slot_width)
        right = round((column + 1) * slot_width)
        top, bottom = spec.row_ranges[row]
        cell = source.crop((left, top, right, bottom))
        resized_height = round(cell.height * shared_scale)
        resized = cell.resize((CONTENT_WIDTH, resized_height), Image.Resampling.LANCZOS)

        frame = Image.new("RGBA", OUTPUT_SIZE, (0, 0, 0, 0))
        frame.alpha_composite(resized, ((OUTPUT_SIZE[0] - CONTENT_WIDTH) // 2, CONTENT_TOP))
        bbox = alpha_bbox(frame)
        if bbox is None:
            raise ValueError(f"{spec.source.name}: expression {name} produced an empty frame")

        output = spec.output_dir / f"{index + 1:02d}_{name}.png"
        frame.save(output, optimize=True)
        outputs.append(output)

    render_preview(outputs, spec.output_dir / "_preview.png", spec.columns)
    return outputs


def render_preview(paths: list[Path], output: Path, columns: int) -> None:
    thumb_size = (100, 150)
    label_height = 24
    rows = (len(paths) + columns - 1) // columns
    preview = Image.new(
        "RGBA",
        (columns * thumb_size[0], rows * (thumb_size[1] + label_height)),
        (24, 25, 31, 255),
    )
    draw = ImageDraw.Draw(preview)
    for index, path in enumerate(paths):
        row, column = divmod(index, columns)
        x = column * thumb_size[0]
        y = row * (thumb_size[1] + label_height)
        thumb = Image.open(path).convert("RGBA").resize(thumb_size, Image.Resampling.LANCZOS)
        preview.alpha_composite(thumb, (x, y))
        draw.text((x + 5, y + thumb_size[1] + 3), path.stem, fill=(235, 225, 198, 255))
    preview.save(output, optimize=True)


def main() -> None:
    total = 0
    for spec in SPECS:
        outputs = slice_sheet(spec)
        total += len(outputs)
        print(f"{spec.output_dir}: {len(outputs)} expressions")
    print(f"Wrote {total} normalized expression portraits")


if __name__ == "__main__":
    main()

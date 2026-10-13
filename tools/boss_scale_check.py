"""BOSS 素材比例体检：把不同来源的师傅素材拉到同一条地面线上对比。

用途：师傅的多个动作来自不同批次（ChatGPT 4x4 图 / Meowa 3D 渲染导出），
每批的渲染分辨率并不一致。这个脚本把它们各自的首帧按原始像素摆在一起，
共用一条地面基准线，直接看出"换动作时角色会不会突然变大变小"。

只读源文件，输出一张对比 PNG。

用法：
    python tools/boss_scale_check.py
"""

from __future__ import annotations

import re
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(os.environ.get("HOMING_STAR_GAME_PROJECT", Path(__file__).resolve().parents[2] / "homeing-star-game"))
PENDING = Path(__file__).resolve().parents[2] / "homeing-star-temp-assert" / "PendingArt" / "character" / "师傅" / "战斗姿态1"
ASSETS = ROOT / "assets" / "sideview" / "characters" / "master"
OUTPUT = Path(os.environ.get("HOMING_STAR_TEST_OUTPUT", Path(__file__).resolve().parents[1] / "artifacts")) / "boss_scale_check.png"

ALPHA_CUTOFF = 128
CANVAS_W = 1180
CANVAS_H = 460
GROUND_Y = 360
LABEL_Y = 378
SCALE_Y = 398

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\msyhl.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in FONT_CANDIDATES:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size)
            except Exception:  # noqa: BLE001
                continue
    return ImageFont.load_default()


def crop_to_content(frame: Image.Image) -> Image.Image | None:
    alpha = frame.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUTOFF else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        return None
    return frame.crop(bbox)


def meowa_sheet(action: str) -> tuple[Image.Image, int, int]:
    """读 Meowa 导出，拿回 (sheet, 格宽, 格高)。"""
    tres = PENDING / action / "image-2_frames.tres"
    text = tres.read_text(encoding="utf-8", errors="replace")
    match = re.search(r'path="([^"]+\.png)"', text)
    if not match:
        raise ValueError(f"{tres} 找不到 sheet")
    sheet_path = tres.parent / match.group(1)
    if not sheet_path.exists():
        raise FileNotFoundError(f"{sheet_path} 不存在（导出不完整）")
    region = re.search(r"region = Rect2\((\d+), (\d+), (\d+), (\d+)\)", text)
    if not region:
        raise ValueError(f"{tres} 找不到 region")
    _, _, w, h = (int(v) for v in region.groups())
    return Image.open(sheet_path).convert("RGBA"), w, h


def adopted_frame(path: Path, cell: tuple[int, int], index: int) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    cw, ch = cell
    cols = im.width // cw
    col = index % cols
    row = index // cols
    return im.crop((col * cw, row * ch, col * cw + cw, row * ch + ch))


def main() -> None:
    entries: list[tuple[str, str, Image.Image]] = []

    adopted = [
        ("已采用 idle", ASSETS / "boss/phase1/idle/master_boss_idle_adopted_128x144_16f.png", (128, 144)),
        ("已采用 walk", ASSETS / "boss/phase1/walk/master_boss_walk_adopted_128x144_16f.png", (128, 144)),
    ]
    for label, path, cell in adopted:
        if path.exists():
            entries.append((label, "ChatGPT 4x4 管线", adopted_frame(path, cell, 0)))

    for action in ["待机", "二阶段待机", "上挑", "冲刺", "旋斩", "变身"]:
        try:
            sheet, cw, ch = meowa_sheet(action)
        except Exception as exc:  # noqa: BLE001
            print(f"跳过 {action}：{exc}")
            continue
        entries.append((f"Meowa {action}", "Meowa 3D 渲染", sheet.crop((0, 0, cw, ch))))

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (250, 249, 245, 255))
    draw = ImageDraw.Draw(canvas)
    font_label = load_font(15)
    font_small = load_font(14)
    font_title = load_font(17)

    draw.text((24, 20), "师傅 BOSS 素材比例体检 — 各来源首帧，共用地面基准线，原始像素不缩放", fill=(40, 38, 34), font=font_title)

    draw.line([(24, GROUND_Y), (CANVAS_W - 24, GROUND_Y)], fill=(180, 150, 110), width=2)
    draw.text((24, GROUND_Y + 6), "地面基准线", fill=(150, 120, 80), font=font_small)

    slot_w = (CANVAS_W - 48) // max(1, len(entries))
    heights: list[tuple[str, int]] = []

    for index, (label, source, frame) in enumerate(entries):
        content = crop_to_content(frame)
        if content is None:
            continue
        h = content.height
        heights.append((label, h))

        cx = 24 + slot_w * index + slot_w // 2
        x = cx - content.width // 2
        y = GROUND_Y - h
        canvas.alpha_composite(content, (x, y))

        draw.text((cx, LABEL_Y), label, fill=(40, 38, 34), font=font_label, anchor="ma")
        draw.text((cx, LABEL_Y + 18), f"{h}px 高", fill=(90, 86, 80), font=font_small, anchor="ma")
        draw.text((cx, SCALE_Y + 16), source, fill=(150, 146, 140), font=font_small, anchor="ma")

    if heights:
        tallest = max(heights, key=lambda item: item[1])
        shortest = min(heights, key=lambda item: item[1])
        ratio = tallest[1] / shortest[1]
        summary = (
            f"最高 {tallest[0]} = {tallest[1]}px ｜ 最矮 {shortest[0]} = {shortest[1]}px "
            f"｜ 相差 {ratio:.2f} 倍"
        )
        draw.text((24, CANVAS_H - 34), summary, fill=(163, 45, 45), font=font_label)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT, optimize=True)
    print(f"已输出：{OUTPUT}")
    for label, h in heights:
        print(f"  {label:<20} {h:>4}px")


if __name__ == "__main__":
    main()

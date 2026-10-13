"""Meowa 导出体检：把 PendingArt 里的 Meowa 精灵表逐帧量一遍。

用途：在把 Meowa 导出接进游戏之前，先回答三个问题——
1. 每个动作的画布格（cell）是多大，是否跨动作统一；
2. 每帧的角色脚底线在哪，帧间漂移多少像素（这是序列帧"抖不抖"的生死线）；
3. 每帧的角色中心横向偏移多少像素（决定会不会左右抽动）。

只用标准库 + Pillow。不修改任何源文件，纯读取。

用法：
    python tools/meowa_export_report.py
    python tools/meowa_export_report.py --root "PendingArt/character/师傅/战斗姿态1"
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ALPHA_CUTOFF = 128


def parse_frames_tres(tres_path: Path) -> tuple[Path, list[tuple[int, int, int, int]]]:
    """从 Meowa 的 SpriteFrames 资源里读出 sheet 路径与逐帧区域。

    直接使用 Meowa 自己写下的 region，而不是按 256 去猜网格——
    实测各动作的格宽并不都是 256，猜错会整张错位。
    """
    text = tres_path.read_text(encoding="utf-8", errors="replace")

    sheet_match = re.search(r'path="([^"]+\.png)"', text)
    if not sheet_match:
        raise ValueError(f"{tres_path} 里找不到 sheet 引用")
    sheet_path = tres_path.parent / sheet_match.group(1)

    regions_by_id: dict[str, tuple[int, int, int, int]] = {}
    for match in re.finditer(
        r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]'
        r'.*?region = Rect2\((-?\d+), (-?\d+), (\d+), (\d+)\)',
        text,
        re.DOTALL,
    ):
        ident, x, y, w, h = match.groups()
        regions_by_id[ident] = (int(x), int(y), int(w), int(h))

    # Meowa 把 frames 写成 JSON 风格（"frames": [{...}]），不是 Godot 原生的
    # frames = [...]，所以这里匹配带引号的键名。
    frames_match = re.search(r'"frames"\s*:\s*\[(.*?)\]\s*,?\s*"loop"', text, re.DOTALL)
    if not frames_match:
        frames_match = re.search(r'"frames"\s*:\s*\[(.*)\]', text, re.DOTALL)
    if not frames_match:
        raise ValueError(f"{tres_path} 里找不到 frames 数组")

    ordered: list[tuple[int, int, int, int]] = []
    for ident in re.findall(r'SubResource\("([^"]+)"\)', frames_match.group(1)):
        if ident in regions_by_id:
            ordered.append(regions_by_id[ident])

    if not ordered:
        raise ValueError(f"{tres_path} 的 frames 数组为空")

    return sheet_path, ordered


def frame_metrics(sheet: Image.Image, region: tuple[int, int, int, int]) -> dict | None:
    """量单帧的透明包围盒与脚底线。"""
    x, y, w, h = region
    try:
        frame = sheet.crop((x, y, x + w, y + h))
    except Exception:
        return None

    alpha = frame.getchannel("A")
    mask = alpha.point(lambda v: 255 if v >= ALPHA_CUTOFF else 0)
    bbox = mask.getbbox()
    if bbox is None:
        return None

    left, top, right, bottom = bbox
    return {
        "foot_y": bottom,
        "top_y": top,
        "height": bottom - top,
        "left": left,
        "right": right,
        "center_x": (left + right) / 2.0,
        "width": right - left,
        "cell_w": w,
        "cell_h": h,
    }


def spread(values: list[float]) -> tuple[float, float, float]:
    return min(values), max(values), max(values) - min(values)


def audit_action(tres_path: Path) -> dict:
    sheet_path, regions = parse_frames_tres(tres_path)
    sheet = Image.open(sheet_path).convert("RGBA")

    metrics = [m for m in (frame_metrics(sheet, r) for r in regions) if m]
    empty = len(regions) - len(metrics)

    cells = {(m["cell_w"], m["cell_h"]) for m in metrics}
    foot_min, foot_max, foot_drift = spread([m["foot_y"] for m in metrics])
    cx_min, cx_max, cx_drift = spread([m["center_x"] for m in metrics])
    heights = [m["height"] for m in metrics]

    return {
        "action": tres_path.parent.name,
        "frames": len(metrics),
        "empty_frames": empty,
        "cells": sorted(cells),
        "foot_min": foot_min,
        "foot_max": foot_max,
        "foot_drift": foot_drift,
        "cx_drift": cx_drift,
        "height_avg": sum(heights) / len(heights) if heights else 0,
        "height_min": min(heights) if heights else 0,
        "height_max": max(heights) if heights else 0,
        "sheet": sheet_path.name,
        "sheet_size": f"{sheet.width}x{sheet.height}",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=r"PendingArt/character/师傅/战斗姿态1",
        help="Meowa 导出所在目录",
    )
    args = parser.parse_args()

    search_root = (ROOT / args.root) if not Path(args.root).is_absolute() else Path(args.root)
    tres_files = sorted(search_root.glob("*/image-2_frames.tres"))
    if not tres_files:
        print(f"未找到任何 image-2_frames.tres，检查路径：{search_root}")
        return

    print(f"扫描目录：{search_root}")
    print()
    header = (
        f"{'动作':<12}{'帧数':>5}{'空帧':>5}{'格宽x格高':>12}"
        f"{'脚底漂移':>9}{'中心漂移':>9}{'角色高':>8}"
    )
    print(header)
    print("-" * len(header.encode("gbk", errors="replace")))

    results = []
    for tres in tres_files:
        try:
            info = audit_action(tres)
        except Exception as exc:  # noqa: BLE001
            print(f"{tres.parent.name:<12}  读取失败：{exc}")
            continue
        results.append(info)
        cell_text = ",".join(f"{w}x{h}" for w, h in info["cells"]) or "-"
        print(
            f"{info['action']:<12}{info['frames']:>5}{info['empty_frames']:>5}"
            f"{cell_text:>12}{info['foot_drift']:>9.0f}{info['cx_drift']:>9.1f}"
            f"{info['height_avg']:>8.0f}"
        )

    if not results:
        return

    print()
    print("=== 结论 ===")
    all_cells: set[tuple[int, int]] = set()
    for info in results:
        all_cells.update(info["cells"])
    if len(all_cells) > 1:
        print(f"格尺寸跨动作不统一：{sorted(all_cells)}")
    else:
        print(f"格尺寸跨动作统一：{sorted(all_cells)}")

    worst_foot = max(results, key=lambda i: i["foot_drift"])
    print(
        f"脚底漂移最大：{worst_foot['action']} "
        f"{worst_foot['foot_drift']:.0f}px（{worst_foot['foot_min']:.0f}→{worst_foot['foot_max']:.0f}）"
    )
    worst_cx = max(results, key=lambda i: i["cx_drift"])
    print(f"中心漂移最大：{worst_cx['action']} {worst_cx['cx_drift']:.1f}px")

    heights = [i["height_avg"] for i in results]
    print(f"角色平均高度：{min(heights):.0f}～{max(heights):.0f}px（跨动作波动 {max(heights) - min(heights):.0f}px）")


if __name__ == "__main__":
    main()

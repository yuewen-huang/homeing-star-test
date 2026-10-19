"""师傅素材风格归队实测：把 Meowa 渲染输出压到岚的美术语言，看三段演进后的观感。

为什么写这个脚本
----------------
"降级感"的来源不是画布尺寸、也不是明暗抖动，而是师傅与岚处在两套美术语言里。
把两边的实体数据摆在一起，差距有两个独立维度：

    维度        岚（成品像素包 + 本项目量化管线）   师傅（Meowa 渲染导出）
    色数        单体 19~32 色 / 全库合并 104 色      单体 4792~6827 色
    明度        不透明像素暗部占比 18.1%             不透明像素暗部占比 58.7%

量化只解决第一个维度。第二个维度要单独一步：把师傅的亮度直方图匹配到岚的直方图。
本脚本就是验证这两步连做之后，师傅能不能和岚站在同一个画面里。

三步流水（全部在 2D 层，与 tools/process_master_boss_adopted_sheets.py 的做法同源）
----------------------------------------------------------------------------------
    1. alpha 二值化    —— 去掉渲染留下的抗锯齿半透明边，硬边是像素画的前提
    2. 明度匹配        —— 亮度直方图匹配到岚，按增益缩放 RGB，保持色相不变
    3. N 色量化        —— 中位切分、不抖动，把连续渐变收成有限色块

注意第 3 步必须在第 2 步之后：先量化再改明度会破坏调色板的稳定性。

产出
----
1. _诊断/palette_match_check.png —— 2 行 × 4 列演进对照图
2. 终端色数 / 暗部占比表

已知边界（实测结论，不要对这一步期待过高）
------------------------------------------
量化 + 明度匹配能把师傅"拉进岚的语言"，但修不了"同动作内明暗随姿势崩塌"：
上挑 f16 原图暗部 86.0%，压到 32 色后是 86.9%，量化对此完全无能为力。
那一层问题在 3D 渲染端（材质与光照随姿态变化），不在 2D 后处理的能力范围内。
"""
from __future__ import annotations

import re
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(os.environ.get("HOMING_STAR_GAME_PROJECT", Path(__file__).resolve().parents[2] / "homeing-star-game"))
MEOWA = Path(__file__).resolve().parents[2] / "homeing-star-temp-assert/PendingArt/character/师傅/战斗姿态1"
OUT = Path(os.environ.get("HOMING_STAR_TEST_OUTPUT", Path(__file__).resolve().parents[1] / "artifacts"))
LAN = ROOT / "assets/characters/lan/body"
MASTER = ROOT / "assets/bosses/master/body/boss/phase1"

ALPHA_CUT = 128               # 硬边阈值，与项目既有脚本保持一致
QUANT_COLORS = 32             # tools/build_instant_dash_skill_assets.py 使用的色数
NORMAL_HEIGHT = 300           # 预览图上统一角色高度（只影响预览，不动素材）
DARK_LEVEL = 60               # 判定"暗部"的亮度上限


# ---------------------------------------------------------------- 素材读取

def load_meowa(action: str, index: int) -> Image.Image:
    """按 tres 中 region 的出现顺序，取 Meowa 某动作的第 index 帧。"""
    tres = MEOWA / action / "image-2_frames.tres"
    text = tres.read_text(encoding="utf-8", errors="replace")
    ref = tres.parent / re.search(r'path="([^"]+)"', text).group(1)
    sheet = Image.open(ref).convert("RGBA")
    regions: list[tuple[int, int, int, int]] = []
    seen = set()
    for r in re.findall(r"region = Rect2\((-?\d+), (-?\d+), (\d+), (\d+)\)", text):
        key = tuple(int(v) for v in r)
        if key not in seen:
            seen.add(key)
            regions.append(key)
    x, y, w, h = regions[index]
    return sheet.crop((x, y, x + w, y + h))


def lan_widest_attack_frame() -> Image.Image:
    """在岚 attack_1x 里自动挑出内容最展开的一帧，作为"要够到的标准"参照。

    该表 2560×64 横排，格子宽度靠内容分布推断，不硬编码。
    """
    sheet = Image.open(LAN / "attack/attack_1x.png").convert("RGBA")
    best, best_area, best_box = None, -1, None
    for cell_w in (64, 60, 58, 56, 80, 96):
        cols = sheet.width // cell_w
        if cols < 4:
            continue
        for c in range(cols):
            frame = sheet.crop((c * cell_w, 0, (c + 1) * cell_w, sheet.height))
            bb = frame.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0).getbbox()
            area = (bb[2] - bb[0]) * (bb[3] - bb[1]) if bb else 0
            if area > best_area:
                best, best_area, best_box = frame, area, (cell_w, c)
    return best


# ---------------------------------------------------------------- 目标分布

def lan_luminance_cdf() -> list[float]:
    """从岚全部素材的不透明像素，构建亮度累积分布——这就是"岚的语言"。"""
    hist = [0] * 256
    for p in sorted(LAN.rglob("*.png")):
        im = Image.open(p).convert("RGBA")
        a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
        lum = im.convert("L")
        ap, lp = a.load(), lum.load()
        for y in range(im.height):
            for x in range(im.width):
                if ap[x, y] >= ALPHA_CUT:
                    hist[lp[x, y]] += 1
    total = sum(hist) or 1
    cdf, acc = [], 0
    for h in hist:
        acc += h
        cdf.append(acc / total)
    return cdf


# ---------------------------------------------------------------- 三步处理

def harden_alpha(frame: Image.Image) -> Image.Image:
    """第 1 步：alpha 二值化，消掉抗锯齿毛边。"""
    alpha = frame.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    out = frame.copy()
    out.putalpha(alpha)
    return out


def match_luminance(frame: Image.Image, target_cdf: list[float], strength: float = 1.0) -> Image.Image:
    """第 2 步：把亮度直方图匹配到目标分布，按增益缩放 RGB 以保持色相。

    做法是标准的直方图匹配：找到本图亮度 CDF 在目标 CDF 上的对应点，
    得到新亮度，再以新旧亮度之比缩放 RGB 通道。

    strength 是在"不动"与"完全匹配"之间插值的旋钮，实测必须暴露它：
    完全匹配（1.0）会同时抹掉角色的体积层次，深青外套被拉成浅粉调，
    BOSS 的压迫感消失；0.4~0.6 一般能在"暗部读得出"和"留住厚重感"之间取平衡。
    """
    a = frame.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    ap = a.load()
    lum = frame.convert("L")
    lp = lum.load()

    hist = [0] * 256
    for y in range(frame.height):
        for x in range(frame.width):
            if ap[x, y] >= ALPHA_CUT:
                hist[lp[x, y]] += 1
    total = sum(hist) or 1
    src_cdf, acc = [], 0
    for h in hist:
        acc += h
        src_cdf.append(acc / total)

    mapping = [0] * 256
    for v in range(256):
        c = src_cdf[v]
        idx = 0
        while idx < 255 and target_cdf[idx] < c:
            idx += 1
        mapping[v] = idx

    out = frame.copy()
    op = out.load()
    for y in range(frame.height):
        for x in range(frame.width):
            if ap[x, y] < ALPHA_CUT:
                continue
            r, g, b, al = op[x, y]
            l0 = lp[x, y]
            # 插值：strength=0 保持原样，strength=1 完全对齐目标分布
            l1 = int(round(l0 + (mapping[l0] - l0) * strength))
            gain = 1.0 if l0 == 0 else l1 / l0
            op[x, y] = (
                min(255, int(r * gain)),
                min(255, int(g * gain)),
                min(255, int(b * gain)),
                al,
            )
    return out


def quantize(frame: Image.Image, colors: int = QUANT_COLORS) -> Image.Image:
    """第 3 步：中位切分量化，不抖动。"""
    alpha = frame.getchannel("A")
    rgb = (
        frame.convert("RGB")
        .quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        .convert("RGB")
    )
    return Image.merge("RGBA", (*rgb.split(), alpha))


def pipeline(frame: Image.Image, target_cdf: list[float], strength: float, colors: int = QUANT_COLORS) -> Image.Image:
    return quantize(match_luminance(harden_alpha(frame), target_cdf, strength), colors)


# ---------------------------------------------------------------- 度量与出图

def stats(im: Image.Image) -> tuple[int, float]:
    a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    ap = a.load()
    lum = im.convert("L")
    lp = lum.load()
    colors, dark, total = set(), 0, 0
    for y in range(im.height):
        for x in range(im.width):
            if ap[x, y] >= ALPHA_CUT:
                total += 1
                colors.add(im.getpixel((x, y)))
                if lp[x, y] < DARK_LEVEL:
                    dark += 1
    return len(colors), (dark / total * 100 if total else 0.0)


def crop_to_content(im: Image.Image) -> Image.Image:
    bb = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0).getbbox()
    return im.crop(bb) if bb else im


def scale_to_height(im: Image.Image, height: int = NORMAL_HEIGHT) -> Image.Image:
    im = crop_to_content(im)
    s = height / im.height
    return im.resize((max(1, round(im.width * s)), height), Image.Resampling.NEAREST)


def build_figure(target_cdf: list[float]) -> Path:
    lan_idle = Image.open(LAN / "idle/idle.png").convert("RGBA").crop((0, 0, 46, 55))
    lan_atk = lan_widest_attack_frame()

    master_idle = Image.open(
        MASTER / "idle/master_boss_idle_128x144_16f.png"
    ).convert("RGBA").crop((0, 0, 128, 144))
    up16 = load_meowa("上挑", 16)

    rows = [
        (
            "A. 风格归队三步：岚(参照) → 师傅原图 → 硬边+32色 → 再加明度匹配",
            [
                ("岚 idle（成品像素包）", lan_idle, None),
                ("师傅 idle（游戏内在用）", master_idle, None),
                ("师傅 idle → 硬边+32色", master_idle, "quant"),
                ("师傅 idle → 硬边+32色+明度匹配", master_idle, "full"),
            ],
        ),
        (
            "B. 崩坏帧能被救到哪一步：上挑 f16（暗部 86%）",
            [
                ("岚 attack_1x（内容最展开帧）", lan_atk, None),
                ("Meowa 上挑 f16（原图）", up16, None),
                ("上挑 f16 → 硬边+32色", up16, "quant"),
                ("上挑 f16 → 硬边+32色+明度匹配", up16, "full"),
            ],
        ),
    ]

    print(f"{'素材':<40}{'不透明色数':>10}{'暗部占比':>10}")
    print("-" * 62)
    canvases = []
    for _, items in rows:
        for label, im, mode in items:
            if mode == "quant":
                out = quantize(harden_alpha(im))
            elif mode == "full":
                out = pipeline(im, target_cdf)
            else:
                out = im
            c, dark = stats(out)
            print(f"{label:<40}{c:>10}{dark:>9.1f}%")
            canvases.append((label, out, mode))

    pad, gapx, gapy = 24, 20, 58
    cellw = NORMAL_HEIGHT + 40
    colw = cellw + gapx
    roww = NORMAL_HEIGHT + gapy + 46
    W = pad * 2 + colw * 4
    H = pad * 2 + roww * 2 + 30

    img = Image.new("RGB", (W, H), (241, 239, 232))
    d = ImageDraw.Draw(img)
    try:
        f_title = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 21)
        f_small = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
    except OSError:
        f_title = f_small = ImageFont.load_default()

    y, idx = pad, 0
    for title, _ in rows:
        d.text((pad, y), title, fill=(40, 40, 38), font=f_title)
        y += 32
        for col in range(4):
            label, im, _ = canvases[idx]
            idx += 1
            x0 = pad + col * colw
            scaled = scale_to_height(im)
            box = Image.new("RGB", (cellw, NORMAL_HEIGHT + 16), (226, 224, 217))
            box.paste(scaled, ((cellw - scaled.width) // 2, 8), scaled)
            img.paste(box, (x0, y))
            d.text((x0 + 2, y - 20), label, fill=(66, 66, 62), font=f_small)
        y += roww + 20

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "palette_match_check.png"
    img.save(path)
    return path


if __name__ == "__main__":
    print(f"硬边阈值={ALPHA_CUT}  量化色数={QUANT_COLORS}  预览角色高={NORMAL_HEIGHT}px")
    print("正在从岚的全部素材构建目标亮度分布...")
    target = lan_luminance_cdf()
    print(f"目标分布就绪（岚不透明像素亮度的累积分布）\n")
    print(f"{'素材':<40}{'不透明色数':>10}{'暗部占比':>10}")
    print("-" * 62)
    p = build_figure(target)
    print(f"\n对照图已写入 {p}")

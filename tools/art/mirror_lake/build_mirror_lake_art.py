#!/usr/bin/env python3
"""镜湖 (Mirror Lake) 水墨分层美术管线 / AI ink-wash art pipeline.

Builds the four runtime layers of the 镜湖 map from the AI-generated ink-wash sources in ./sources
(GenerateImage candidates, picked per segment — see prompts.md) plus procedural water:

    01_paper.png          宣纸底 + 阳/阴 天空（不含日月），1280x1110，不滚动 (ratio 0)
    02_far_mountains.png  远山：3 张 AI 远景交叠淡入淡出拼成长卷 (ratio 0.12)
    03_mid_scenery.png    中景：AI 单景(松/竹/亭/舟/桥/石/柳/湖心楼)抠成透明 PNG 后摆放 (ratio 0.5)
    04_lake_ground.png    地面：近岸石/芦苇/汀步 + 立体水面(透视水纹/椭圆涟漪/高光带) (ratio 1.0)
    sun.png / moon.png    落日（阳）/ 月亮（阴）独立精灵，256x256 透明 PNG，与 01_paper 同视差(0)，阴阳切换时交叉淡变
    player_water_contact.png  主角脚下的接触阴影/涟漪(运行时挂在主角脚下)

World width has ONE source of truth: `const WORLD_LENGTH` in mirror_lake.gd (read by regex here, and by
the test). Layer width = ceil((1280 + (W-1280)*ratio)/32)*32. Every image is 1110 px tall; rows 0..554
are 阳 (yang), 555..1109 are 阴 (yin = flipped, tone-inverted, ripple-distorted reflection + water band).
The waterline (world y = 555 = SideviewMapLayout.GROUND_BASELINE_Y) is the seam between rows 554/555.

Usage:  python build_mirror_lake_art.py --gd path/to/mirror_lake.gd --out DIR [--preview DIR] [--only paper far ...]
Needs:  numpy, scipy, Pillow, Noto Serif CJK (colophon/seal). The PC has no Python; run on any box with these.
"""
import argparse
import math
import os
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter, gaussian_filter1d, maximum_filter, map_coordinates

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "sources")

VIEW_W, VIEW_H = 1280, 720
YH = 555                     # rows above the waterline (yang half)
H = YH * 2                   # 1110
RATIO_FAR, RATIO_MID, RATIO_GROUND = 0.12, 0.5, 1.0
WORLD_W = 15360              # overwritten from mirror_lake.gd
STAND_D = 64                 # rows below the waterline where the feet stand (STAND_OFFSET_Y in mirror_lake.gd)


def read_world_length(gd_path):
    text = open(gd_path, encoding="utf-8").read()
    m = re.search(r"^const\s+WORLD_LENGTH\s*:?=\s*([0-9.]+)", text, re.M)
    if not m:
        raise SystemExit("WORLD_LENGTH not found in " + gd_path)
    return int(float(m.group(1)))


def read_stand_offset(gd_path):
    text = open(gd_path, encoding="utf-8").read()
    m = re.search(r"^const\s+STAND_OFFSET_Y\s*:?=\s*([0-9.]+)", text, re.M)
    return int(float(m.group(1))) if m else 0


def layer_width(ratio):
    return int(math.ceil((VIEW_W + (WORLD_W - VIEW_W) * ratio) / 32.0) * 32)


def boss_center_x():
    return WORLD_W - VIEW_W          # contract: BOSS_ARENA_CENTER_X = WORLD_LENGTH - VIEW_WIDTH


PAPER_YANG = np.array([242, 235, 219], np.float32)      # 宣纸 off-white
INK_YANG = np.array([36, 37, 35], np.float32)           # 墨
PAPER_YIN = np.array([30, 34, 36], np.float32)          # 阴: 墨底
INK_YIN = np.array([206, 203, 188], np.float32)         # 阴: 淡墨变亮
MIST_YIN = np.array([58, 66, 69], np.float32)
CINNABAR = np.array([178, 40, 31], np.float32)          # 朱砂
CINNABAR_YIN = np.array([132, 52, 44], np.float32)

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc",
    "C:/Windows/Fonts/msyhbd.ttc", "C:/Windows/Fonts/simsun.ttc",
]


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def rnorm(rng, shape, sx, sy):
    n = gaussian_filter(rng.standard_normal(shape).astype(np.float32), (sy, sx), mode="reflect")
    return (n - n.mean()) / (n.std() + 1e-6)


def noise1d(rng, n, sigma):
    v = gaussian_filter1d(rng.standard_normal(n), sigma, mode="reflect")
    return (v - v.mean()) / (v.std() + 1e-9)


def screen(a, b):
    return 1.0 - (1.0 - a) * (1.0 - b)


# ---------------------------------------------------------------- layer buffers

class Layer:
    """Yang-half accumulation buffers. ink: dark ink density; mist: paper-coloured veil;
    red: cinnabar. apply_mist veils everything painted so far (depth), add_ink paints on top."""

    def __init__(self, width):
        self.w = width
        self.ink = np.zeros((YH, width), np.float32)
        self.mist = np.zeros((YH, width), np.float32)
        self.red = np.zeros((YH, width), np.float32)

    def add_ink(self, arr, x0, y0, tone=1.0):
        self._blend(self.ink, arr * tone, x0, y0)

    def add_red(self, arr, x0, y0):
        self._blend(self.red, arr, x0, y0)

    def apply_mist(self, m):
        self.ink *= (1.0 - m)
        self.red *= (1.0 - m)
        self.mist = screen(self.mist, m)

    def _blend(self, dst, arr, x0, y0):
        h, w = arr.shape
        xa, ya = max(0, x0), max(0, y0)
        xb, yb = min(self.w, x0 + w), min(YH, y0 + h)
        if xa >= xb or ya >= yb:
            return
        src = arr[ya - y0:yb - y0, xa - x0:xb - x0]
        dst[ya:yb, xa:xb] = screen(dst[ya:yb, xa:xb], np.clip(src, 0, 1))


def compose_half(layer, ink_c, mist_c, red_c):
    """-> straight-alpha float RGBA (YH, W, 4) for one half."""
    ai, am, ar = layer.ink, layer.mist, layer.red
    a_ink_over_mist = ai + am * (1 - ai)
    prem = ink_c[None, None, :] * ai[..., None] + mist_c[None, None, :] * (am * (1 - ai))[..., None]
    a = a_ink_over_mist
    # red over everything
    prem = red_c[None, None, :] * ar[..., None] + prem * (1 - ar[..., None])
    a = ar + a * (1 - ar)
    rgb = prem / np.maximum(a[..., None], 1e-5)
    return np.concatenate([rgb, a[..., None] * 255.0], axis=2)



def to_png(arr, path):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    img.save(path, optimize=True)
    print("wrote", path, img.size, os.path.getsize(path) // 1024, "KB")


# ---------------------------------------------------------------- brush canvas
def dry_mask(rng, shape, strength, scale=(0.7, 2.6)):
    """干笔飞白: fibre-like holes in a stroke."""
    n = rnorm(rng, shape, scale[0], scale[1]) + 0.5 * rnorm(rng, shape, 2.5, 6.0)
    return 1.0 - strength * smoothstep(0.1, 1.6, n)



def mist_band(rng, width, yc, sy, sx_noise, amp, extent=None):
    rows = np.arange(YH)[:, None].astype(np.float32)
    prof = np.exp(-((rows - yc) ** 2) / (2 * sy ** 2))
    mod = 0.55 + 0.45 * np.clip(0.5 + 0.5 * noise1d(rng, width, sx_noise), 0, 1)
    return np.clip(prof * mod[None, :] * amp, 0, 1)



def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    raise SystemExit("no CJK font found")


def seal_array(text, size, seed):
    """朱砂白文印章 (white text knocked out of a red block), returns float alpha (h, w)."""
    rng = np.random.default_rng(seed)
    ss = 4
    img = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size * ss - 1, size * ss - 1], fill=255)
    pad = int(size * 0.1)
    d.rectangle([pad * ss, pad * ss, (size - pad) * ss - 1, (size - pad) * ss - 1], fill=0)
    d.rectangle([int(pad * 1.5) * ss, int(pad * 1.5) * ss, (size - int(pad * 1.5)) * ss - 1, (size - int(pad * 1.5)) * ss - 1], fill=255)
    f = load_font(int(size * 0.34 * ss))
    inner = size - 2 * int(pad * 1.5)
    cell = inner * ss / 2
    chars = [text[0], text[1], text[2], text[3]] if len(text) == 4 else [text[0], text[1], "", ""]
    # right-to-left, top-to-bottom: [0]=top-right [1]=bottom-right [2]=top-left [3]=bottom-left
    pos = [(1, 0), (1, 1), (0, 0), (0, 1)]
    for ch, (cx, cy) in zip(chars, pos):
        if not ch:
            continue
        x = int(pad * 1.5) * ss + cx * cell + cell / 2
        y = int(pad * 1.5) * ss + cy * cell + cell / 2
        d.text((x, y), ch, font=f, fill=0, anchor="mm")
    a = np.asarray(img.resize((size, size), Image.LANCZOS), np.float32) / 255.0
    a *= 1.0 - 0.5 * smoothstep(0.7, 1.5, rnorm(rng, a.shape, 0.9, 0.9))   # worn edges / ink pits
    return np.clip(a, 0, 1)


def calligraphy(text, size, seed, tone=1.0):
    rng = np.random.default_rng(seed)
    f = load_font(size)
    ss = 3
    w, h = size + 24, int(len(text) * size * 1.12) + 12
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    for i, ch in enumerate(text):
        d.text((w * ss / 2, (i * size * 1.12 + size * 0.6) * ss), ch, font=f, fill=255, anchor="mm")
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    a = a * dry_mask(rng, a.shape, 0.55, (0.7, 2.2))
    a = np.maximum(a, 0)
    return screen(a * tone, gaussian_filter(a, 1.6) * 0.18)



def build_paper():
    rng = np.random.default_rng(4004)
    w = VIEW_W
    yang = np.ones((YH, w, 3), np.float32) * PAPER_YANG
    rows = np.arange(YH)[:, None, None].astype(np.float32)
    # slightly greyer toward the top, bright 留白 glow at the horizon
    t = (rows / YH)
    tint = np.array([-9, -8, -9], np.float32) * (1 - t) ** 1.5 + np.array([5, 5, 6], np.float32) * t ** 4
    yang = yang + tint
    # 水墨渲染: very pale wash clouds
    cloud = rnorm(rng, (YH, w), 160, 28)
    yang += (np.clip(cloud, -0.5, 2.0)[..., None] * np.array([-5, -5, -4.5], np.float32))
    fib = rnorm(rng, (YH, w), 0.6, 2.4)
    yang += fib[..., None] * 2.2
    mott = rnorm(rng, (YH, w), 8, 8)
    yang += mott[..., None] * 1.8
    # 落日 / 月亮不再烤进纸底：它们是独立精灵（sun.png / moon.png，见 build_celestials），由阴阳切换交叉淡变。
    # yin: dark paper, lighter near the waterline, with its own fibres
    yin = np.ones((YH, w, 3), np.float32) * PAPER_YIN
    r2 = np.arange(YH)[::-1][:, None, None].astype(np.float32) / YH     # 0 at the seam? (flip later)
    near = (1 - np.arange(YH)[:, None, None] / YH)                       # 1 at seam (row YH-1)
    near = (np.arange(YH)[:, None, None] / YH)                           # 0 top..1 at seam (before flip)
    yin = yin + near ** 3 * np.array([20, 22, 22], np.float32) - (1 - near) * np.array([6, 6, 6], np.float32)
    yin += fib[..., None] * 2.4 + mott[..., None] * 2.0
    yin += (np.clip(cloud, -0.5, 2.0)[..., None] * np.array([3, 3.5, 3.5], np.float32))
    yin = yin[::-1]
    full = np.concatenate([yang, yin], axis=0)
    alpha = np.ones((H, w, 1), np.float32) * 255
    return np.concatenate([np.clip(full, 0, 255), alpha], axis=2)




# ================================================================ AI sprite handling
def _resize_f(a, w, h):
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((max(1, int(w)), max(1, int(h))), Image.LANCZOS), np.float32)


def ink_alpha(path, gain=1.18, floor=0.05):
    """宣纸底 -> 透明 ("multiply to alpha"): alpha = 1 - pixel/paper, so ink keeps its tone and paper vanishes."""
    im = np.asarray(Image.open(path).convert("L"), np.float32) / 255.0
    small = im[::8, ::8]
    local = gaussian_filter(maximum_filter(small, size=45), 6)
    bg = np.asarray(Image.fromarray(local, "F").resize((im.shape[1], im.shape[0]), Image.BICUBIC), np.float32)
    bg = np.maximum(bg, 0.93 * np.percentile(im, 99))
    a = (1.0 - im / np.maximum(bg, 0.05) - floor) * gain / (1.0 - floor)
    return np.clip(a, 0.0, 1.0)


def load_sprite(name, ybase=None, fade=14, gain=1.18, floor=0.05, feather=0.05):
    """-> alpha array cropped to its ink bounding box. `ybase` (source rows) cuts off baked-in water/reflection."""
    a = ink_alpha(os.path.join(SRC, name + ".jpg"), gain, floor)
    if ybase is not None:
        a[ybase:] = 0
        ramp = np.linspace(1.0, 0.0, fade, dtype=np.float32) ** 1.3
        a[ybase - fade:ybase] *= ramp[:, None]
    mask = a > 0.18
    rows, cols = np.where(mask)
    # robust bbox: ignore stray specks (need >=3 inked pixels in the row/column)
    ry = np.where(mask.sum(1) >= 3)[0]
    cx = np.where(mask.sum(0) >= 2)[0]
    y0, y1, x0, x1 = ry.min(), ry.max(), cx.min(), cx.max()
    pad = 6
    out = a[max(0, y0 - pad):y1 + 1 + pad, max(0, x0 - pad):x1 + 1 + pad].copy()
    # soft left/right edges: some AI vignettes have a hard vertical cut in their background ridge/mist
    fw = int(min(max(feather, 0.05) * out.shape[1], 260))
    ramp = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, fw))).astype(np.float32)
    out[:, :fw] *= ramp[None, :]
    out[:, -fw:] *= ramp[::-1][None, :]
    return out


SPRITES = {   # name -> (source, ybase or None)
    "pine_a": ("mid1_c3", None), "pine_b": ("mid1_c2", None),
    "bamboo_a": ("mid2_c3", None), "bamboo_b": ("mid2_c1", None),
    "pavilion_a": ("mid3_c3", None), "pavilion_b": ("mid3_c1", None),
    "boat": ("mid4_c3", 505), "bridge": ("mid5_c2", 570),
    "pillars_a": ("mid6_c3", None), "pillars_b": ("mid6_c1", None),
    "willow_a": ("mid7_c3", None), "willow_b": ("mid7_c2", None),
    "landmark": ("mid8_c2", 556),
    "rocks_a": ("g1_c2", None), "rocks_b": ("g1_c3", None),
    "reeds_a": ("g2_c1", None), "reeds_b": ("g2_c2", None), "reeds_c": ("g2_c3", None),
    "slabs_a": ("g3_c3", None), "slabs_b": ("g3_c2", None),
}
_cache = {}


def sprite(name):
    if name not in _cache:
        src, yb = SPRITES[name]
        _cache[name] = load_sprite(src, yb, fade=30 if name == "bridge" else 14, feather=0.22 if name == "landmark" else 0.05)
    return _cache[name]


def place(layer, name, cx, target_h, flip=False, tone=1.0, sink=3):
    a = sprite(name)
    if flip:
        a = a[:, ::-1]
    s = target_h / a.shape[0]
    a = _resize_f(a, a.shape[1] * s, target_h)
    x0 = int(round(cx - a.shape[1] / 2))
    y0 = int(round(YH + sink - a.shape[0]))
    layer.add_ink(a, x0, y0, tone)


# ================================================================ yin (reflection) + water
REFL_INK = np.array([150, 154, 146], np.float32)   # 倒影墨色：比 INK_YIN 暗一档，水面才读得出高光/暗纹

def over(dst_rgb, dst_a, src_rgb, src_a):
    out_a = src_a + dst_a * (1 - src_a)
    out_rgb = (src_rgb * src_a[..., None] + dst_rgb * (dst_a * (1 - src_a))[..., None]) / np.maximum(out_a[..., None], 1e-5)
    return out_rgb, out_a


def reflection(layer, rng, distort=0.0, blur=0.9, strength=0.9, far_fade=0.55):
    """阴: flipped, tone-inverted copy; distort = amplitude of the static ripple bands (px at the foreground)."""
    yin = compose_half(layer, REFL_INK, MIST_YIN, CINNABAR_YIN)[::-1].copy()      # row 0 = waterline
    h, w = yin.shape[:2]
    d = np.arange(h, dtype=np.float32)[:, None]
    if distort > 0:
        t = np.clip(d / 370.0, 0, 1.4)
        n = rnorm(rng, (h, w), 70, 1.5)
        dx = n * (0.8 + distort * t) + 0.5 * np.sin(d * (0.55 + 0.25 * t)) * (0.4 + distort * 0.5 * t)
        dy = rnorm(rng, (h, w), 45, 3.0) * (0.3 + 1.1 * t)
        ys = (d + dy).astype(np.float32)
        xs = (np.arange(w, dtype=np.float32)[None, :] + dx).astype(np.float32)
        coords = np.stack([np.broadcast_to(ys, (h, w)), xs])
        for c in range(4):
            yin[..., c] = map_coordinates(yin[..., c], coords, order=1, mode="nearest")
    for c in range(4):
        yin[..., c] = gaussian_filter(yin[..., c], (blur, 0.5))
    fade = 1.0 - far_fade * smoothstep(0, 430, d)
    yin[..., 3] *= fade * strength
    return yin


def water_surface(w, rng):
    """立体水面 (static art): straight-alpha float RGBA (555, w, 4), row 0 = waterline, alpha 0..1.

    Perspective: toward the viewer (row index d grows) strokes get longer, thicker, darker and sparser;
    toward the waterline they are short, thin, pale and dense. Plus flattened ring ripples, a soft sheen
    band hugging the horizon and a calm patch right at the walking line."""
    hh = YH
    ss = 2
    d_axis = np.arange(hh, dtype=np.float32)[:, None]
    light = Image.new("L", (w, hh * ss), 0)
    dark = Image.new("L", (w, hh * ss), 0)
    dl, dd = ImageDraw.Draw(light), ImageDraw.Draw(dark)

    def lens(draw, cx, cy, length, thick, val):
        n = 12
        xs = np.linspace(-0.5, 0.5, n)
        prof = np.clip(1 - (2 * xs) ** 2, 0, 1) ** 0.6
        th = max(thick * ss, 1.0)
        top = [(cx + x * length, cy * ss - p * th * 0.5) for x, p in zip(xs, prof)]
        bot = [(cx + x * length, cy * ss + p * th * 0.4) for x, p in zip(xs[::-1], prof[::-1])]
        draw.polygon(top + bot, fill=int(np.clip(val, 0, 255)))

    # --- horizontal brush-stroke 水纹 lines, spacing grows with distance
    d = 9.0
    while d < 470:
        t = d / 370.0
        length0 = 36 + 0.95 * d
        thick0 = 0.9 + 0.026 * d
        gapf = 0.45 + d / 150.0
        p_dark = 0.9 * float(smoothstep(110, 360, d))
        x = rng.uniform(0, length0 * gapf)
        while x < w:
            ln = length0 * rng.uniform(0.55, 1.45)
            th = thick0 * rng.uniform(0.7, 1.3)
            calm = float(smoothstep(10, 46, d)) * (1.0 - 0.92 * float(np.exp(-(((d - STAND_D) / 24.0) ** 2))))
            if rng.random() < p_dark:
                lens(dd, x, d, ln, th, 255 * (0.42 + 0.35 * min(t, 1.2)) * calm)
            else:
                lens(dl, x, d, ln, th, 255 * (0.55 - 0.25 * min(t, 1.2)) * calm)
            x += ln * (1.0 + gapf * rng.uniform(0.35, 1.7))
        d += 2.6 + 0.085 * d * rng.uniform(0.7, 1.3)

    # --- soft elliptical ring ripples, flattened by perspective
    n_rings = int(w / 300)
    for _ in range(n_rings):
        dcen = 30 + 380 * rng.random() ** 1.15
        cx = rng.uniform(0, w)
        if abs(dcen - STAND_D) < 52:      # keep the water at the feet calm (room for a future splash effect)
            continue
        rx = (16 + 0.78 * dcen) * rng.uniform(0.6, 1.5)
        ry = rx * (0.10 + 0.00035 * dcen)
        wd = max(1, int(round((0.8 + 0.012 * dcen) * ss)))
        near_fade = 1.0 - 0.6 * float(smoothstep(140, 430, dcen))
        for k, (mul, val) in enumerate(((1.0, 0.62 * near_fade), (1.5, 0.42 * near_fade), (2.05, 0.26 * near_fade))):
            a0 = rng.uniform(0, 360)
            segs = int(rng.integers(2, 4))
            for s in range(segs):
                st = a0 + s * 360 / segs + rng.uniform(0, 25)
                en = st + 360 / segs * rng.uniform(0.45, 0.8)
                box = [cx - rx * mul, (dcen - ry * mul) * ss, cx + rx * mul, (dcen + ry * mul) * ss]
                box[1], box[3] = box[1], box[3]
                dl.arc([box[0], box[1], box[2], box[3]], st, en, fill=int(255 * val * (1.0 - 0.3 * k)), width=wd)

    def to_arr(img):
        arr = np.asarray(img.resize((w, hh), Image.BOX), np.float32) / 255.0
        return gaussian_filter(arr, (0.45, 0.9))

    la, da = to_arr(light), to_arr(dark)
    nm = rnorm(rng, (hh, w), 2.4, 0.8)
    dry = 1.0 - 0.5 * smoothstep(0.2, 1.6, nm)
    la, da = la * dry, da * dry

    rgb = np.zeros((hh, w, 3), np.float32)
    a = np.zeros((hh, w), np.float32)
    # water body tone: lifted slate near the horizon, sinking into ink toward the viewer
    body_a = np.broadcast_to((0.46 * np.exp(-d_axis / 130.0) + 0.16), (hh, w))
    rgb, a = over(rgb, a, np.broadcast_to(np.array([84, 96, 98], np.float32), (hh, w, 3)), body_a.astype(np.float32))
    shade_a = np.broadcast_to(0.30 * smoothstep(140, 470, d_axis), (hh, w)).astype(np.float32)
    rgb, a = over(rgb, a, np.broadcast_to(np.array([6, 8, 10], np.float32), (hh, w, 3)), shade_a)
    # sheen band under the horizon (sky glow on the water), streaked along x
    xmod = (0.72 + 0.28 * np.clip(0.5 + 0.5 * noise1d(rng, w, 160), 0, 1))[None, :]
    sheen = (0.34 * np.exp(-((d_axis - 15) ** 2) / (2 * 11.0 ** 2)) + 0.10 * np.exp(-d_axis / 85.0)) * xmod
    sheen = gaussian_filter(sheen.astype(np.float32), (0, 24)) * 1.0
    rgb, a = over(rgb, a, np.broadcast_to(np.array([186, 194, 190], np.float32), (hh, w, 3)), np.clip(sheen, 0, 1).astype(np.float32))
    rgb, a = over(rgb, a, np.broadcast_to(np.array([4, 6, 8], np.float32), (hh, w, 3)), np.clip(da, 0, 1))
    rgb, a = over(rgb, a, np.broadcast_to(np.array([202, 210, 205], np.float32), (hh, w, 3)), np.clip(la, 0, 1))
    return np.concatenate([rgb, a[..., None]], axis=2)


def stack_layer(layer, rng, distort, blur, strength, far_fade=0.55, water=None):
    yang = compose_half(layer, INK_YANG, PAPER_YANG, CINNABAR)
    yin = reflection(layer, rng, distort, blur, strength, far_fade)
    if water is not None:
        # water body/strokes sit UNDER the reflection ink, so the reflection stays readable
        rgb2, a2 = over(water[..., :3], water[..., 3], yin[..., :3], yin[..., 3] / 255.0 * 0.92)
        yin = np.concatenate([rgb2, a2[..., None] * 255.0], axis=2)
    return np.concatenate([yang, yin], axis=0)


# ================================================================ layers
def mid_x(x):
    return x * layer_width(RATIO_MID) / 8320.0


def build_far():
    rng = np.random.default_rng(11)
    w = layer_width(RATIO_FAR)
    # (source, scale, left x as fraction of W-range, flip) — far3 (calm mist) sits at the boss end
    plan = [("far1_c2", 0.72, 0.0, False), ("far2_c2", 0.62, 0.2236, False),
            ("far1_c2", 0.72, 0.4749, True), ("far2_c2", 0.62, 0.6709, True), ("far3_c3", 0.80, 1.0, False)]
    num = np.zeros((YH, w), np.float32)
    den = np.zeros((YH, w), np.float32)
    placed = []
    for name, sc, f, flip in plan:
        a = ink_alpha(os.path.join(SRC, name + ".jpg"), gain=1.30, floor=0.04)
        if flip:
            a = a[:, ::-1]
        a = _resize_f(a, a.shape[1] * sc, a.shape[0] * sc)
        wi = a.shape[1]
        x0 = int(round((w - wi) * f))
        y0 = int(YH + 8 - a.shape[0])
        placed.append((a, x0, y0))
    for i in range(len(placed) - 1):   # every junction must overlap, or the fade leaves a hard seam
        assert placed[i][1] + placed[i][0].shape[1] - placed[i + 1][1] >= 200, "far panoramas do not overlap enough"
    for i, (a, x0, y0) in enumerate(placed):
        wi = a.shape[1]
        wt = np.ones(wi, np.float32)
        if i > 0:
            ov = max(1, placed[i - 1][1] + placed[i - 1][0].shape[1] - x0)
            wt[:ov] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ov))
        if i < len(placed) - 1:
            ov = max(1, x0 + wi - placed[i + 1][1])
            wt[-ov:] = np.minimum(wt[-ov:], 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, ov)))
        ya, yb = max(0, y0), min(YH, y0 + a.shape[0])
        num[ya:yb, x0:x0 + wi] += a[ya - y0:yb - y0] * wt[None, :]
        den[ya:yb, x0:x0 + wi] += wt[None, :]
    ink = np.where(den > 1e-4, num / np.maximum(den, 1e-4), 0.0).astype(np.float32)
    layer = Layer(w)
    layer.ink = ink
    # keep the foot of the mountains veiled in mist right down to the waterline
    layer.apply_mist(mist_band(rng, w, 540, 22, 80, 0.85))
    layer.apply_mist(mist_band(rng, w, 470, 40, 120, 0.25))
    return stack_layer(layer, rng, distort=0.0, blur=2.2, strength=0.62, far_fade=0.5)


MID_PLAN = [   # (sprite, x in 8320-wide mid space, height px, flip) — zones: entry <1600, puzzle one <4160, puzzle two <6720, boss
    ("willow_a", 420, 330, False), ("pine_a", 1030, 420, False),
    ("bamboo_a", 1720, 380, False), ("pavilion_a", 2330, 330, False), ("boat", 2960, 150, False),
    ("pillars_a", 3520, 400, False), ("bridge", 4060, 250, False),
    ("pine_b", 4650, 390, True), ("bamboo_b", 5250, 360, True), ("willow_b", 5850, 340, True),
    ("pavilion_b", 6360, 320, True),
    ("landmark", 7360, 360, False), ("boat", 7960, 125, True),
]


def build_mid():
    rng = np.random.default_rng(22)
    w = layer_width(RATIO_MID)
    layer = Layer(w)
    prev = None
    for name, x, hgt, flip in MID_PLAN:
        assert name != prev, "same segment twice in a row: " + name
        prev = name
        place(layer, name, mid_x(x), hgt, flip)
    layer.apply_mist(mist_band(rng, w, 538, 18, 90, 0.78))
    layer.apply_mist(mist_band(rng, w, 480, 34, 140, 0.30))
    return stack_layer(layer, rng, distort=5.0, blur=1.6, strength=0.62, far_fade=0.6)


GROUND_PLAN = [   # (sprite, world x, height, flip). The boss arena (W-1280 +-780) is kept clear on purpose.
    ("rocks_a", 150, 270, False),
    ("rocks_b", 900, 140, False), ("reeds_a", 1750, 230, False), ("slabs_a", 2350, 60, False),
    ("rocks_a", 3100, 150, True), ("reeds_b", 3700, 210, False), ("slabs_b", 4300, 55, False),
    ("rocks_b", 5000, 170, True), ("reeds_c", 5800, 240, True), ("slabs_a", 6400, 65, True),
    ("reeds_a", 7100, 200, True),
    ("rocks_a", 8100, 150, False), ("reeds_b", 8800, 230, True), ("slabs_b", 9500, 60, True),
    ("rocks_b", 10200, 160, False), ("reeds_c", 10900, 210, False), ("slabs_a", 11600, 60, False),
    ("reeds_a", 12300, 220, True),
    ("rocks_a", 12950, 130, True),
    ("rocks_b", 15180, 280, True),
]


def build_ground():
    rng = np.random.default_rng(33)
    w = layer_width(RATIO_GROUND)
    layer = Layer(w)
    prev = None
    for name, x, hgt, flip in GROUND_PLAN:
        assert name != prev, "same segment twice in a row: " + name
        prev = name
        place(layer, name, x * w / WORLD_W, hgt, flip)
    # small colophon + the one 朱砂 seal near the spawn
    cal = calligraphy("镜湖", 30, 5, tone=0.9)
    cx0 = int(1120 * w / WORLD_W)
    layer.add_ink(cal, cx0, 118)
    layer.add_red(seal_array("镜湖", 30, 9) * 0.92, cx0 + 14, 118 + cal.shape[0] + 8)
    layer.apply_mist(mist_band(rng, w, 548, 9, 70, 0.55))
    water = water_surface(w, rng)
    return stack_layer(layer, rng, distort=9.0, blur=0.9, strength=0.66, far_fade=0.6, water=water)


# ================================================================ 日 / 月（独立精灵）
CEL = 256                       # 精灵边长；圆心在正中
SUN_WORLD_C = (905, 252)        # 落日圆心在 01_paper 里的位置（与旧版烤进纸底的位置一致）
MOON_WORLD_C = (905, 252)       # 月亮圆心（与落日重合，同一块天空）
SUN_R, MOON_R = 54, 52


def build_sun():
    """淡朱砂日轮：与旧版烤进纸底的公式完全一致（alpha = 0.72 * 边缘平滑），所以阳态画面不变。"""
    yy, xx = np.mgrid[0:CEL, 0:CEL].astype(np.float32)
    dd = np.sqrt((xx - CEL / 2) ** 2 + (yy - CEL / 2) ** 2)
    a = smoothstep(SUN_R + 3, SUN_R - 3, dd) * 0.72
    rgb = np.ones((CEL, CEL, 3), np.float32) * np.array([226, 140, 112], np.float32)
    return np.concatenate([rgb, a[..., None] * 255], axis=2)


def build_moon():
    """水墨月：浅银白圆盘，轮廓微微毛边，盘面有淡墨晕（月海），一缕云雾横过下半，外圈一层冷白的晕染。"""
    rng = np.random.default_rng(7007)
    yy, xx = np.mgrid[0:CEL, 0:CEL].astype(np.float32)
    cx = cy = CEL / 2
    dx, dy = xx - cx, yy - cy
    ang = np.arctan2(dy, dx)
    dd = np.sqrt(dx ** 2 + dy ** 2)
    # 轮廓毛边：半径随角度做低频起伏，再加一点点细噪
    wob = gaussian_filter1d(rng.standard_normal(360), 22, mode="wrap")
    wob = wob / (np.abs(wob).max() + 1e-6)
    idx = ((ang + np.pi) / (2 * np.pi) * 359).astype(int)
    r = MOON_R + wob[idx] * 1.0 + rnorm(rng, (CEL, CEL), 3.0, 3.0) * 0.25
    disc = smoothstep(r + 2.5, r - 2.5, dd)
    # 盘面：银白底 + 淡墨月海 + 边缘略亮（留白感）
    base = np.array([226, 229, 224], np.float32)
    maria = np.clip(rnorm(rng, (CEL, CEL), 9, 8) * 0.5 + 0.1, 0, 1) * np.clip(1 - dd / MOON_R, 0, 1) ** 0.5
    maria *= 0.9
    ink = np.array([118, 126, 124], np.float32)
    rim = np.clip((dd - MOON_R * 0.72) / (MOON_R * 0.28), 0, 1)
    rgb = base[None, None, :] * (1 - maria[..., None] * 0.55) + ink[None, None, :] * maria[..., None] * 0.55
    rgb = rgb + rim[..., None] * np.array([6, 6, 6], np.float32)
    dry = np.clip(rnorm(rng, (CEL, CEL), 1.4, 1.4) * 2.2, -5, 5)           # 干笔颗粒
    rgb = rgb + dry[..., None]
    # 云雾：一条横向被拉长的噪声带，压在盘面下 1/3，也向两侧飘出盘外
    mist_n = 0.65 * rnorm(rng, (CEL, CEL), 26, 6) + 0.35 * rnorm(rng, (CEL, CEL), 10, 3)
    ywarp = rnorm(rng, (CEL, CEL), 30, 30) * 7.0
    band = np.exp(-((yy - (cy + 18) + ywarp) ** 2) / (2 * 13.0 ** 2))
    mist = smoothstep(-0.5, 0.9, mist_n) * band * np.clip((CEL / 2 - np.abs(dx)) / 50.0, 0, 1)
    disc_a = disc * (1 - mist * 0.62)
    # 外圈晕染：冷白，向外衰减；云雾飘出盘外的部分是同色淡雾
    halo = np.exp(-((np.maximum(dd - MOON_R, 0)) ** 2) / (2 * 26.0 ** 2)) * (dd > MOON_R - 2) * 0.24
    halo *= np.clip(1.0 - np.maximum(dd - MOON_R * 2.3, 0) / 18.0, 0, 1)
    veil = mist * (1 - disc) * 0.34
    halo_rgb = np.array([205, 214, 218], np.float32)
    a_out = np.clip(disc_a + (1 - disc_a) * np.clip(halo * (1 - disc) + veil, 0, 1), 0, 1)
    wd = disc_a[..., None]
    wh = ((1 - disc_a) * np.clip(halo * (1 - disc) + veil, 0, 1))[..., None]
    col = (rgb * wd + halo_rgb[None, None, :] * wh) / np.maximum(wd + wh, 1e-5)
    return np.concatenate([np.clip(col, 0, 255), a_out[..., None] * 255], axis=2)


def build_celestials(out_dir):
    to_png(build_sun(), os.path.join(out_dir, "sun.png"))
    to_png(build_moon(), os.path.join(out_dir, "moon.png"))



def build_contact():
    """主角脚下的接触阴影 + 两圈浅涟漪，192x48，中心 = 脚点(水线)。"""
    w, h = 192, 48
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w / 2, h / 2
    r = np.sqrt(((xx - cx) / 62.0) ** 2 + ((yy - cy) / 8.0) ** 2)
    shadow = np.exp(-(r ** 2) * 1.6) * 0.62
    ring1 = np.exp(-(((np.sqrt(((xx - cx) / 84.0) ** 2 + ((yy - cy) / 11.0) ** 2)) - 1.0) ** 2) / (2 * 0.06 ** 2)) * 0.34
    ring2 = np.exp(-(((np.sqrt(((xx - cx) / 40.0) ** 2 + ((yy - cy) / 5.5) ** 2)) - 1.0) ** 2) / (2 * 0.08 ** 2)) * 0.30
    ang = np.arctan2((yy - cy), (xx - cx))
    gap = 0.55 + 0.45 * np.sin(ang * 3 + 0.8)
    pale = np.clip((ring1 + ring2) * gap, 0, 1)
    a = np.clip(shadow + pale, 0, 1)
    rgb = np.zeros((h, w, 3), np.float32)
    dark_c, pale_c = np.array([6, 8, 10], np.float32), np.array([200, 208, 203], np.float32)
    wp = pale / np.maximum(a, 1e-4)
    rgb = dark_c[None, None, :] * (1 - wp[..., None]) + pale_c[None, None, :] * wp[..., None]
    return np.concatenate([rgb, a[..., None] * 255.0], axis=2)


# ================================================================ preview
def parallax_off(cam_x, ratio):
    return int(round((cam_x - VIEW_W / 2) * ratio))


def render_frame(imgs, cam_x, cam_y=195, player=True):
    frame = Image.fromarray(imgs["paper"][cam_y:cam_y + VIEW_H].astype(np.uint8), "RGBA")
    for key, ratio in (("far", RATIO_FAR), ("mid", RATIO_MID), ("ground", RATIO_GROUND)):
        arr = imgs[key]
        off = parallax_off(cam_x, ratio)
        crop = arr[cam_y:cam_y + VIEW_H, off:off + VIEW_W]
        frame = Image.alpha_composite(frame, Image.fromarray(crop.astype(np.uint8), "RGBA"))
    if player:
        d = ImageDraw.Draw(frame)
        px, py = VIEW_W // 2, YH - cam_y
        d.rounded_rectangle([px - 14, py - 90, px + 14, py], 6, fill=(60, 90, 140, 255))
        d.ellipse([px - 12, py - 106, px + 12, py - 82], fill=(240, 205, 170, 255))
    return frame.convert("RGB")


def build_previews(imgs, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    n = WORLD_W // VIEW_W
    cams = [int(VIEW_W / 2 + k * VIEW_W) for k in range(n)]
    cams[-1] = WORLD_W - VIEW_W // 2
    frames = []
    for i, c in enumerate(cams):
        f = render_frame(imgs, c)
        f.save(os.path.join(out_dir, "np_frame_%02d.png" % i))
        frames.append(f)
    cols = 3
    rows = (len(frames) + cols - 1) // cols
    tw, th = 640, 360
    sheet = Image.new("RGB", (cols * tw + (cols - 1) * 6, rows * th + (rows - 1) * 6), (255, 0, 255))
    for i, f in enumerate(frames):
        sheet.paste(f.resize((tw, th), Image.LANCZOS), ((i % cols) * (tw + 6), (i // cols) * (th + 6)))
    sheet.save(os.path.join(out_dir, "np_sheet.png"))
    print("previews ->", out_dir)


def to_png(arr, path):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    img.save(path, optimize=True)
    print("wrote", path, img.size, os.path.getsize(path) // 1024, "KB", flush=True)


def main():
    global WORLD_W, STAND_D
    ap = argparse.ArgumentParser()
    ap.add_argument("--gd", required=True, help="path to mirror_lake.gd (reads WORLD_LENGTH)")
    ap.add_argument("--out", default="out")
    ap.add_argument("--preview", default=None, help="dir for numpy preview frames + contact sheet")
    ap.add_argument("--only", nargs="*", default=None)
    a = ap.parse_args()
    WORLD_W = read_world_length(a.gd)
    STAND_D = read_stand_offset(a.gd)
    print("STAND_OFFSET_Y =", STAND_D)
    print("WORLD_LENGTH =", WORLD_W, "widths:", [1280, layer_width(RATIO_FAR), layer_width(RATIO_MID), layer_width(RATIO_GROUND)])
    os.makedirs(a.out, exist_ok=True)
    builders = {"paper": ("01_paper.png", build_paper), "far": ("02_far_mountains.png", build_far),
                "mid": ("03_mid_scenery.png", build_mid), "ground": ("04_lake_ground.png", build_ground)}
    imgs = {}
    for key, (fname, fn) in builders.items():
        p = os.path.join(a.out, fname)
        if a.only and key not in a.only and os.path.exists(p):
            imgs[key] = np.asarray(Image.open(p).convert("RGBA"), np.float32)
            continue
        print("building", key, flush=True)
        arr = fn()
        imgs[key] = arr
        to_png(arr, p)
    if not a.only or "contact" in a.only:
        to_png(build_contact(), os.path.join(a.out, "player_water_contact.png"))
    if not a.only or "celestial" in a.only:
        build_celestials(a.out)
    if a.preview:
        build_previews(imgs, a.preview)


if __name__ == "__main__":
    main()

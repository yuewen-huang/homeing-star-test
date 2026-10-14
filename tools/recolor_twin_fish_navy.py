"""Recolor the approved white twin fish atlas to blue-black with blue fin glints."""
from pathlib import Path
import argparse
import colorsys
from functools import lru_cache
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont


def blend(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def ramp(stops, value):
    for (low, a), (high, b) in zip(stops, stops[1:]):
        if value <= high:
            return blend(a, b, max(0, (value - low) / (high - low)))
    return stops[-1][1]


BODY_RAMP = [(0.0, (4, 8, 17)), (0.55, (8, 15, 29)),
             (0.80, (13, 25, 44)), (0.91, (21, 38, 65)),
             (0.96, (40, 63, 107)), (1.0, (72, 101, 157))]
FIN_RAMP = [(0.0, (2, 6, 15)), (0.45, (6, 17, 44)),
            (0.65, (9, 30, 74)), (0.80, (14, 43, 97)),
            (0.91, (25, 57, 116)), (1.0, (47, 83, 145))]


@lru_cache(maxsize=None)
def navy(rgb):
    r, g, b = rgb
    hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    # Keep the existing violet eye detail readable against the new dark skin.
    if saturation > 0.15 and (hue > 0.73 or hue < 0.03):
        return rgb
    luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    blue_material = max(0, min(1, (b - r - 4) / 58))
    # User correction: swap the light/dark material assignments. Original pale
    # skin and fin tips take the blue highlight ramp; original blue grooves take
    # the blue-black ramp. Keep the authored shading within each material.
    return blend(ramp(FIN_RAMP, luminance), ramp(BODY_RAMP, luminance), blue_material)


def checker(size):
    image = Image.new('RGBA', size, (230, 232, 235))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], 8):
        for x in range(0, size[0], 8):
            if (x // 8 + y // 8) % 2:
                draw.rectangle((x, y, x + 7, y + 7), fill=(212, 216, 222))
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    assert args.source.resolve() != args.output.resolve()
    preview_dir = args.output.parent / '双子黑_预览_20261014'
    preview_dir.mkdir(parents=True, exist_ok=True)
    before_deepen = preview_dir / '双子黑-walk_浅区加深前.png'
    if args.output.exists() and not before_deepen.exists():
        before_deepen.write_bytes(args.output.read_bytes())
    before_swap = preview_dir / '双子黑-walk_区域对调前.png'
    if args.output.exists() and not before_swap.exists():
        before_swap.write_bytes(args.output.read_bytes())
    previous = preview_dir / '双子黑-walk_深藏青旧版.png'
    if args.output.exists() and not previous.exists():
        previous.write_bytes(args.output.read_bytes())
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    original_file = Image.open(args.source)
    original = original_file.convert('RGBA')
    assert original.size == (1024, 1024), 'Expected the approved 4 x 4 atlas'
    output = original.copy()
    before = original.tobytes()
    after = bytearray(before)
    changed = 0
    for offset in range(0, len(before), 4):
        if not before[offset + 3]:
            continue
        rgb = tuple(before[offset:offset + 3])
        replacement = navy(rgb)
        after[offset:offset + 3] = bytes(replacement)
        changed += replacement != rgb
    output = Image.frombytes('RGBA', original.size, bytes(after))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Preserve physical-resolution metadata when present, but not stale ICC
    # transforms that could shift the chosen sRGB navy colors in other viewers.
    save_options = {'dpi': original_file.info['dpi']} if 'dpi' in original_file.info else {}
    output.save(args.output, **save_options)
    reopened = Image.open(args.output).convert('RGBA')
    assert reopened.size == original.size
    assert reopened.getchannel('A').tobytes() == original.getchannel('A').tobytes()
    assert reopened.tobytes() == output.tobytes()
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == source_hash

    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
    comparison = Image.new('RGBA', (1080, 340), (243, 245, 248))
    draw = ImageDraw.Draw(comparison)
    for index, (image, title) in enumerate([(original, '双子白 · 原稿'), (output, '双子黑 · 深蓝配蓝黑')]):
        tile = checker((256, 256))
        tile.alpha_composite(image.crop((0, 0, 256, 256)))
        # Crop the common authored area only for preview; atlas is unchanged.
        tile = tile.crop((24, 74, 230, 181)).resize((494, 257), Image.Resampling.NEAREST)
        x = 26 + index * 530
        comparison.alpha_composite(tile, (x, 64))
        draw.text((x + 8, 20), title, fill=(23, 32, 49), font=font)
    comparison.convert('RGB').save(preview_dir / '双子白与双子黑_对比.png')
    if previous.exists():
        revision = Image.new('RGBA', (1080, 340), (243, 245, 248))
        draw = ImageDraw.Draw(revision)
        for index, (image, title) in enumerate([(Image.open(previous).convert('RGBA'), '旧版 · 过暗'),
                                               (output, '新版 · 浅区深蓝 / 蓝区蓝黑')]):
            tile = checker((256, 256))
            tile.alpha_composite(image.crop((0, 0, 256, 256)))
            tile = tile.crop((24, 74, 230, 181)).resize((494, 257), Image.Resampling.NEAREST)
            x = 26 + index * 530
            revision.alpha_composite(tile, (x, 64))
            draw.text((x + 8, 20), title, fill=(23, 32, 49), font=font)
        revision.convert('RGB').save(preview_dir / '深藏青旧版与蓝黑新版_对比.png')
    if before_swap.exists():
        swapped = Image.new('RGBA', (1080, 340), (243, 245, 248))
        draw = ImageDraw.Draw(swapped)
        for index, (image, title) in enumerate([(Image.open(before_swap).convert('RGBA'), '对调前'),
                                               (output, '对调后 · 浅区深蓝 / 蓝区蓝黑')]):
            tile = checker((256, 256))
            tile.alpha_composite(image.crop((0, 0, 256, 256)))
            tile = tile.crop((24, 74, 230, 181)).resize((494, 257), Image.Resampling.NEAREST)
            x = 26 + index * 530
            swapped.alpha_composite(tile, (x, 64))
            draw.text((x + 8, 20), title, fill=(23, 32, 49), font=font)
        swapped.convert('RGB').save(preview_dir / '明暗区域对调_对比.png')
    if before_deepen.exists():
        deepened = Image.new('RGBA', (1080, 340), (243, 245, 248))
        draw = ImageDraw.Draw(deepened)
        for index, (image, title) in enumerate([(Image.open(before_deepen).convert('RGBA'), '加深前'),
                                               (output, '加深后 · 深蓝配蓝黑')]):
            tile = checker((256, 256))
            tile.alpha_composite(image.crop((0, 0, 256, 256)))
            tile = tile.crop((24, 74, 230, 181)).resize((494, 257), Image.Resampling.NEAREST)
            x = 26 + index * 530
            deepened.alpha_composite(tile, (x, 64))
            draw.text((x + 8, 20), title, fill=(23, 32, 49), font=font)
        deepened.convert('RGB').save(preview_dir / '浅区蓝色加深_对比.png')
    frames = []
    for index in range(16):
        x, y = (index % 4) * 256, (index // 4) * 256
        tile = checker((256, 256))
        tile.alpha_composite(output.crop((x, y, x + 256, y + 256)))
        frames.append(tile.convert('RGB').resize((768, 768), Image.Resampling.NEAREST))
    frames[0].save(preview_dir / '双子黑-walk.gif', save_all=True, append_images=frames[1:],
                   duration=90, loop=0, disposal=2)
    sheet_preview = checker(output.size)
    sheet_preview.alpha_composite(output)
    sheet_preview.convert('RGB').save(preview_dir / '双子黑-walk_浅底预览.png')
    report = {
        'source': str(args.source), 'output': str(args.output),
        'source_sha256': source_hash, 'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
        'canvas': list(output.size), 'grid': [4, 4], 'frame_size': [256, 256], 'frames': 16,
        'alpha_byte_identical': True, 'source_unchanged': True, 'pixel_layout_unchanged': True,
        'recolored_pixels': changed, 'body_ramp': BODY_RAMP, 'fin_ramp': FIN_RAMP,
        'revision': 'Pale source regions use deeper blue; original blue regions retain blue-black',
        'existing_violet_eye_preserved': True, 'preview_duration_ms': 90,
        'preview_timing_note': 'PNG has no authored timing; GIF uses 90ms solely for preview.',
    }
    (preview_dir / '校验记录.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

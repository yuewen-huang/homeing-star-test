"""Reduce a treant concept to a small, six-colour sprite without dithering.

Keeps the source intact. The enlarged preview always uses nearest neighbour.
"""
from pathlib import Path
import argparse
import colorsys
import json

from PIL import Image, ImageDraw

PALETTE = [
    (39, 22, 15),      # outline / wood shadow
    (123, 85, 57),     # wood
    (174, 137, 95),    # wood highlight
    (45, 64, 33),      # moss shadow
    (104, 144, 73),    # leaves / moss light
    (255, 235, 111),   # eyes
]


def palette_index(rgb):
    r, g, b = rgb
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if r > 190 and g > 180 and r - g < 35 and b < 210 and 0.10 < h < 0.19:
        return 5
    if g > r * 1.04 and g > b * 1.15:
        return 3 if v < 0.36 else 4
    choices = range(3)
    return min(choices, key=lambda i: sum((rgb[c] - PALETTE[i][c]) ** 2 for c in range(3)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--width', type=int, default=24)
    parser.add_argument('--height', type=int, default=40)
    parser.add_argument('--body-width', type=int, default=20)
    parser.add_argument('--preview-scale', type=int, default=12)
    args = parser.parse_args()
    source = Image.open(args.source).convert('RGBA')
    mask = source.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError('Source contains no opaque subject')
    cropped = source.crop(bbox)
    scale = min(args.body_width / cropped.width, (args.height - 4) / cropped.height)
    body_size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    # BOX removes the original soft, oversized pixel texture before assigning
    # the exact palette. No error diffusion and no per-pixel alpha survive.
    reduced = cropped.resize(body_size, Image.Resampling.BOX)
    # Tiny eyes disappear when averaged with bark. Preserve the source eye
    # coverage separately before reducing the rest of the artwork.
    eyes = Image.new('L', cropped.size)
    for y in range(cropped.height):
        for x in range(cropped.width):
            r, g, b, a = cropped.getpixel((x, y))
            if a >= 128 and palette_index((r, g, b)) == 5:
                eyes.putpixel((x, y), 255)
    eyes = eyes.resize(body_size, Image.Resampling.BOX)
    body = Image.new('RGBA', body_size)
    for y in range(body.height):
        for x in range(body.width):
            r, g, b, a = reduced.getpixel((x, y))
            index = 5 if eyes.getpixel((x, y)) >= 48 else palette_index((r, g, b))
            body.putpixel((x, y), (0, 0, 0, 0) if a < 128 else (*PALETTE[index], 255))
    # Merge isolated bark speckles and thin internal streaks into broad clusters.
    # Preserve silhouette boundary pixels, greens and the eye coverage.
    wood = {(*p, 255) for p in PALETTE[:3]}
    for _ in range(2):
        previous = body.copy()
        for y in range(1, body.height - 1):
            for x in range(1, body.width - 1):
                if previous.getpixel((x, y)) not in wood:
                    continue
                neighbours = [previous.getpixel((x + dx, y + dy)) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
                if any(p[3] == 0 for p in neighbours):
                    continue
                winner = max(wood, key=neighbours.count)
                if neighbours.count(winner) >= 5:
                    body.putpixel((x, y), winner)
    native = Image.new('RGBA', (args.width, args.height))
    native.paste(body, ((args.width - body.width) // 2, args.height - body.height - 2))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.resolve() == args.source.resolve():
        raise ValueError('Output must be separate from the original')
    native.save(args.output)
    preview = native.resize((native.width * args.preview_scale, native.height * args.preview_scale), Image.Resampling.NEAREST)
    preview_path = args.output.with_name(args.output.stem + '-preview.png')
    preview.save(preview_path)
    rgba = list(native.get_flattened_data())
    colours = sorted(set(p[:3] for p in rgba if p[3]))
    assert len(colours) <= 6
    assert set(p[3] for p in rgba) <= {0, 255}
    # An opaque comparison card makes the visible simplification easy to inspect.
    card = Image.new('RGB', (640, 540), (28, 34, 30))
    draw = ImageDraw.Draw(card)
    original_colours = len({p[:3] for p in source.get_flattened_data() if p[3] >= 128})
    draw.text((30, 16), f'Original: {cropped.width} x {cropped.height} / {original_colours} visible colours', fill=(225, 237, 222))
    draw.text((352, 16), f'Simplified: {body.width} x {body.height} / {len(colours)} colours', fill=(225, 237, 222))
    original = cropped.resize((cropped.width * 7, cropped.height * 7), Image.Resampling.NEAREST)
    card.paste(original, ((320 - original.width) // 2, 516 - original.height), original)
    card.paste(preview, (320 + (320 - preview.width) // 2, 516 - preview.height), preview)
    comparison = args.output.with_name(args.output.stem + '-comparison.png')
    card.save(comparison)
    metadata = {
        'source': str(args.source), 'source_canvas': source.size, 'source_crop': bbox,
        'canvas': native.size, 'body_size': body_size, 'opaque_colours': colours,
        'alpha_levels': [0, 255], 'dither': False, 'preview_scale': args.preview_scale,
        'output': str(args.output), 'preview': str(preview_path),
    }
    args.output.with_suffix('.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(metadata, ensure_ascii=True))


if __name__ == '__main__':
    main()

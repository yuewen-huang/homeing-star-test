"""Create the white twin human form by replacing the authored pixel palette."""
import argparse
import hashlib
from pathlib import Path
import sys

from PIL import Image, ImageDraw


# Match the approved white fish's ivory outer fins and blue inner grooves:
# light flowing ribbons become ivory; inner hair/cloth retain a blue ramp.
# Replace each palette entry uniformly, without creating new contour pixels.
WHITE_PALETTE = {
    (24, 24, 41): (61, 190, 226),
    (24, 40, 74): (94, 215, 241),
    (8, 36, 82): (75, 207, 237),
    (0, 28, 98): (42, 177, 219),
    (49, 48, 74): (151, 238, 252),
    (8, 137, 230): (194, 211, 220),
    (74, 170, 246): (242, 230, 207),
    (74, 218, 255): (255, 243, 224),
    (156, 210, 238): (255, 247, 233),
}

# Source-space hair selection: crown, tied upper locks, bangs and side locks.
# The lower contour follows the forehead, leaving eyes/skin and clothing alone.
HAIR_POLYGON = [(59, 27), (69, 15), (86, 4), (98, 1), (113, 5),
                (123, 11), (129, 19), (137, 25), (143, 41), (143, 56),
                (132, 60), (122, 57), (121, 50), (116, 50), (117, 44),
                (114, 42), (110, 47), (105, 48), (104, 45), (103, 42),
                (99, 46), (97, 50), (94, 47), (94, 43), (85, 42),
                (77, 38), (61, 35)]
HAIR_PALETTE = {
    (24, 24, 41): (245, 242, 233),
    (24, 40, 74): (220, 232, 237),
    (8, 36, 82): (201, 220, 230),
    (0, 28, 98): (184, 209, 224),
    (49, 48, 74): (255, 251, 240),
}


def hair_mask(size):
    if size != (147, 217):
        raise ValueError('Hair selection requires the authored 147 x 217 canvas.')
    mask = Image.new('L', size)
    ImageDraw.Draw(mask).polygon(HAIR_POLYGON, fill=255)
    return mask


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--preview', type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error('Output must be separate from source.')
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    original_file = Image.open(args.source)
    original = original_file.convert('RGBA')
    output = original.copy()
    pixels = original.load()
    recoloured = output.load()
    hair = hair_mask(original.size).load()
    changed = 0
    for y in range(original.height):
        for x in range(original.width):
            r, g, b, alpha = pixels[x, y]
            rgb = (r, g, b)
            if not alpha or rgb not in WHITE_PALETTE:
                continue
            target = WHITE_PALETTE[rgb]
            if hair[x, y]:
                target = HAIR_PALETTE.get(rgb, target)
            recoloured[x, y] = (*target, alpha)
            changed += 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    options = {'dpi': original_file.info['dpi']} if 'dpi' in original_file.info else {}
    output.save(args.output, **options)
    reopened = Image.open(args.output).convert('RGBA')
    assert reopened.size == original.size
    assert reopened.getchannel('A').tobytes() == original.getchannel('A').tobytes()
    assert reopened.tobytes() == output.tobytes()
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == source_hash
    # Verify both material selections use fixed palette replacements.
    for index, (before, after) in enumerate(zip(original.get_flattened_data(),
                                               reopened.get_flattened_data())):
        x, y = index % original.width, index // original.width
        palette = HAIR_PALETTE if hair[x, y] and before[:3] in HAIR_PALETTE else WHITE_PALETTE
        expected = (*palette.get(before[:3], before[:3]), before[3]) if before[3] else before
        assert after == expected
    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        scale, gap = 3, 24
        preview = Image.new('RGBA', (original.width * scale * 2 + gap,
                                     original.height * scale), (64, 72, 89, 255))
        draw = ImageDraw.Draw(preview)
        for y in range(0, preview.height, 12):
            for x in range(0, preview.width, 12):
                if (x // 12 + y // 12) % 2:
                    draw.rectangle((x, y, x + 11, y + 11), fill=(74, 83, 101, 255))
        for index, picture in enumerate((original, output)):
            preview.alpha_composite(picture.resize((original.width * scale,
                                                    original.height * scale),
                                                   Image.Resampling.NEAREST),
                                    (index * (original.width * scale + gap), 0))
        preview.convert('RGB').save(args.preview)
    print(f'Saved {args.output}; {original.width} x {original.height}; '
          f'{changed} pixels recoloured; alpha and source unchanged.')


if __name__ == '__main__':
    main()

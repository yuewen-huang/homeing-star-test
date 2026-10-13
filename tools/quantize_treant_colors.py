"""Change only RGB colours; preserve dimensions, pixel locations and alpha."""
from pathlib import Path
import argparse
import hashlib
import json

from PIL import Image

PALETTE = (
    (39, 22, 15),
    (123, 85, 57),
    (174, 137, 95),
    (45, 64, 33),
    (104, 144, 73),
    (255, 235, 111),
)


def nearest(rgb):
    r, g, b = rgb
    if r > 190 and g > 180 and r - g < 35 and b < 210:
        candidates = (5,)
    elif g > r * 1.04 and g > b * 1.15:
        candidates = (3, 4)
    else:
        candidates = (0, 1, 2)
    return PALETTE[min(candidates, key=lambda i: sum((rgb[c] - PALETTE[i][c]) ** 2 for c in range(3)))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    original_bytes = args.source.read_bytes()
    source = Image.open(args.source).convert('RGBA')
    result = source.copy()
    result.putdata([(*nearest((r, g, b)), a) for r, g, b, a in source.get_flattened_data()])
    result.save(args.output)
    saved = Image.open(args.output).convert('RGBA')
    assert saved.size == source.size
    assert saved.getchannel('A').tobytes() == source.getchannel('A').tobytes()
    assert saved.getchannel('A').getbbox() == source.getchannel('A').getbbox()
    colours = {p[:3] for p in saved.get_flattened_data() if p[3] > 0}
    assert len(colours) == 6
    assert args.source.read_bytes() == original_bytes
    print(json.dumps({
        'size': saved.size, 'opaque_rgb_palette_size': len(colours),
        'alpha_unchanged': True, 'pixel_locations_unchanged': True,
        'source_sha256': hashlib.sha256(original_bytes).hexdigest(),
        'output': str(args.output),
    }, ensure_ascii=True))


if __name__ == '__main__':
    main()

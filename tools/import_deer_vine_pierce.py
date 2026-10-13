"""Import the user's painted blink-pierce vine for the vine-phase human form.

Source: 360×100 canvas, 16 frames (100 ms). '图层 1' is the launch magic circle at the
staff gem, 'Sprite Sheet' the vine growing right from the circle centre and breaking into
leaves. Both are effect layers, written as two exact 4×4 atlases (no scaling, no recolour):
the runtime keeps the circle at 1.4 and stretches only the vine along its length to fit
the gem-to-target distance (user decision 2026-10-13). Prints the per-frame solid vine
reach from the pivot, which DeerVineStrike.PIERCE_REACH must match. Source unchanged.
"""
from pathlib import Path
import argparse
import hashlib
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

BASE = Path(__file__).resolve().parents[1]
CANVAS = (360, 100)
FRAMES = 16
PIVOT = (50, 52)


def solid_reach(image):
    """Rightmost column of the unbroken vine (gaps over 6 px end it), minus the pivot."""
    alpha = image.getchannel('A').load()
    filled = [any(alpha[x, y] > 128 for y in range(image.height)) for x in range(image.width)]
    start = filled.index(True)
    end, gap = start, 0
    for x in range(start, image.width):
        if filled[x]:
            end, gap = x, 0
        else:
            gap += 1
            if gap > 6:
                break
    return end - PIVOT[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASE.parent/'homeing-star-temp-assert/PendingArt/character/朽角巡林者/16帧绿色魔法藤蔓精灵表.aseprite')
    parser.add_argument('--project', type=Path, default=BASE.parent/'homeing-star-game')
    args = parser.parse_args()
    before = hashlib.sha256(args.source.read_bytes()).hexdigest()
    doc = read(args.source)
    assert doc['canvas'] == CANVAS and len(doc['frames']) == FRAMES, (doc['canvas'], len(doc['frames']))
    assert [layer['name'] for layer in doc['layers']] == ['图层 1', 'Sprite Sheet']
    assert all(frame['duration_ms'] == 100 for frame in doc['frames'])
    atlases = {layer: Image.new('RGBA', (CANVAS[0]*4, CANVAS[1]*4)) for layer in (0, 1)}
    reach = []
    for index in range(FRAMES):
        for layer in (0, 1):
            image, alpha = layer_frame(doc, index, layer)
            assert alpha == 1, ('Unexpected opacity', index, layer)
            atlases[layer].paste(image, (index % 4 * CANVAS[0], index // 4 * CANVAS[1]))
        reach.append(solid_reach(layer_frame(doc, index, 1)[0]))
    target = args.project/'assets/sideview/characters/xiujiao_ranger/human/vfx'
    target.mkdir(parents=True, exist_ok=True)
    for layer, name in ((0, 'vine_pierce_circle.png'), (1, 'vine_pierce.png')):
        texture = target/name
        atlases[layer].save(texture)
        check = Image.open(texture).convert('RGBA')
        for index in range(FRAMES):
            x, y = index % 4 * CANVAS[0], index // 4 * CANVAS[1]
            assert check.crop((x, y, x+CANVAS[0], y+CANVAS[1])).tobytes() == layer_frame(doc, index, layer)[0].tobytes()
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == before
    print('PIERCE_REACH =', reach)
    print('PASS: 16 exact circle and vine frames written to %s; source unchanged' % target)


if __name__ == '__main__':
    main()

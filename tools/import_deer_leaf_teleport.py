"""Import the user's leaf-teleport sequence for the vine-phase human form.

F00-F03 scatter the leaves where the caster leaves; F04-F07 gather them where it
arrives. Cels are copied exactly into one strip; the source is never modified.
"""
from pathlib import Path
import argparse
import hashlib
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

BASE = Path(__file__).resolve().parents[1]
CANVAS = (111, 155)
FRAMES = 8


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASE.parent/'homeing-star-temp-assert/Art/人形态/像素风绿叶传送特效序列.aseprite')
    parser.add_argument('--project', type=Path, default=BASE.parent/'homeing-star-game')
    args = parser.parse_args()
    before = hashlib.sha256(args.source.read_bytes()).hexdigest()
    doc = read(args.source)
    assert doc['canvas'] == CANVAS and len(doc['frames']) == FRAMES, (doc['canvas'], len(doc['frames']))
    assert [layer['name'] for layer in doc['layers']] == ['Sprite Sheet']
    assert all(frame['duration_ms'] == 100 for frame in doc['frames'])
    strip = Image.new('RGBA', (CANVAS[0]*FRAMES, CANVAS[1]))
    for index in range(FRAMES):
        cel, opacity = layer_frame(doc, index, 0)
        assert opacity == 1, ('Unexpected cel opacity', index, opacity)
        strip.paste(cel, (CANVAS[0]*index, 0))
    target = args.project/'assets/sideview/characters/xiujiao_ranger/human/vfx'
    target.mkdir(parents=True, exist_ok=True)
    texture = target/'leaf_teleport.png'
    strip.save(texture)
    check = Image.open(texture).convert('RGBA')
    for index in range(FRAMES):
        x = CANVAS[0]*index
        assert check.crop((x, 0, x+CANVAS[0], CANVAS[1])).tobytes() == layer_frame(doc, index, 0)[0].tobytes()
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == before
    print('PASS: 8 exact cels (100 ms each) written to %s; source unchanged' % texture)


if __name__ == '__main__':
    main()

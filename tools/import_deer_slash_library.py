"""Import the olive-white slash library (6 directions × 3 styles) as antler slash trails.

Source: temp-assert/PendingArt/character/朽角巡林者/白金斩击_Aseprite_20261012/白金斩击_Aseprite_20261012/
变色版本_20261014/3_橄榄绿白/*.aseprite plus 时间轴.json. Each file is a 128×128, 6-frame
sheet with a hidden anchor layer (canvas centre) and two visible effect layers; the
visible layers are composited per frame (honouring layer/cel opacity) into an exact
768×128 strip named by its code (e.g. 05_A.png). Frame timings and the anchor go into
slash_olive.tres metadata. Sources are not modified.
"""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

BASE = Path(__file__).resolve().parents[1]
SOURCE = BASE.parent/'homeing-star-temp-assert/PendingArt/character/朽角巡林者/白金斩击_Aseprite_20261012/白金斩击_Aseprite_20261012/变色版本_20261014/3_橄榄绿白'
CANVAS = (128, 128)
FRAMES = 6


def composite(doc, index):
    frame = Image.new('RGBA', CANVAS)
    for layer_index, layer in enumerate(doc['layers']):
        if not layer['visible']:
            continue
        image, opacity = layer_frame(doc, index, layer_index)
        if opacity < 1.0:
            alpha = image.getchannel('A').point(lambda a: round(a * opacity))
            image.putalpha(alpha)
        frame.alpha_composite(image)
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--project', type=Path, default=BASE.parent/'homeing-star-game')
    args = parser.parse_args()
    timeline = {item['file']: item for item in json.loads((args.source/'时间轴.json').read_text(encoding='utf-8'))}
    target = args.project/'assets/sideview/effects/slash_olive'
    target.mkdir(parents=True, exist_ok=True)
    meta = {}
    for path in sorted(args.source.glob('*.aseprite')):
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        doc = read(path)
        assert doc['canvas'] == CANVAS and len(doc['frames']) == FRAMES, (path.name, doc['canvas'])
        names = [layer['name'] for layer in doc['layers']]
        assert names[0] == '定位点_隐藏' and not doc['layers'][0]['visible'], names
        anchor = layer_frame(doc, 0, 0)[0].getbbox()
        pivot = [(anchor[0] + anchor[2]) / 2.0, (anchor[1] + anchor[3]) / 2.0]
        timings = [frame['duration_ms'] for frame in doc['frames']]
        assert timings == timeline[path.name]['timings_ms'], (path.name, timings)
        strip = Image.new('RGBA', (CANVAS[0]*FRAMES, CANVAS[1]))
        for index in range(FRAMES):
            strip.paste(composite(doc, index), (index*CANVAS[0], 0))
        code = path.name[:4]
        strip.save(target/(code + '.png'))
        assert Image.open(target/(code + '.png')).convert('RGBA').tobytes() == strip.tobytes()
        assert hashlib.sha256(path.read_bytes()).hexdigest() == before
        meta[code] = {'name': path.stem, 'ms': timings, 'pivot': pivot}
    lines = ['[gd_resource type="Resource" format=3]', '', '[resource]',
             'metadata/slashes = ' + json.dumps(json.dumps(meta, ensure_ascii=False), ensure_ascii=False), '']
    (target/'slash_olive.tres').write_text('\n'.join(lines), encoding='utf-8')
    print('PASS: %d slash strips written to %s; sources unchanged' % (len(meta), target))


if __name__ == '__main__':
    main()

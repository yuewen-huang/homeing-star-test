"""Export only God-Come F00, preserving its pixels, canvas and source timing."""
from pathlib import Path
import hashlib
import json
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/character/朽角巡林者/God-Come.aseprite'
DEST = ROOT / 'homeing-star-game/assets/sideview/characters/xiujiao_ranger/human/vfx'


def main():
    raw = SOURCE.read_bytes()
    doc = read(SOURCE)
    assert len(doc['frames']) == 3
    visible = [i for i, layer in enumerate(doc['layers']) if layer['visible']]
    assert len(visible) == 1
    frames = []
    for i in range(3):
        image, opacity = layer_frame(doc, i, visible[0])
        assert opacity == 1
        frames.append(image)
    width, height = doc['canvas']
    # Source has no slice. Use a single bottom-centre ground anchor for all frames.
    pivot = [width / 2, frames[0].getbbox()[3]]
    DEST.mkdir(parents=True, exist_ok=True)
    frames[0].save(DEST / 'god_come.png')
    exported = Image.open(DEST / 'god_come.png').convert('RGBA')
    assert exported.tobytes() == frames[0].tobytes()
    # Approximate solid silhouette in source space, independent of artwork scale.
    bands = []
    for y in range(0, height, 8):
        xs = [x for row in range(y, min(y+8, height)) for x in range(width)
              if frames[0].getpixel((x, row))[3] >= 128]
        if xs:
            bands.append([min(xs), y, max(xs)-min(xs)+1, min(8, height-y)])
    # Sample the retained first pose so particles match the eroding silhouette.
    dust = []
    for y in range(2, height, 10):
        for x in range(2, width, 10):
            r, g, b, a = frames[0].getpixel((x, y))
            if a >= 128:
                dust.append([x-pivot[0], y-pivot[1], r/255, g/255, b/255, a/255])
    data = dict(canvas=list(doc['canvas']), pivot=pivot,
                duration_ms=[doc['frames'][0]['duration_ms']],
                source_frame=0,
                bands=bands, dust=dust, source=SOURCE.name,
                source_sha256=hashlib.sha256(raw).hexdigest())
    encoded = json.dumps(json.dumps(data, separators=(',', ':')), ensure_ascii=False)
    (DEST / 'god_come.tres').write_text(
        '[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+encoded+'\n', encoding='utf-8')
    assert SOURCE.read_bytes() == raw
    print('PASS God-Come: only unchanged F00 exported; source untouched; dust samples:', len(dust))


if __name__ == '__main__':
    main()

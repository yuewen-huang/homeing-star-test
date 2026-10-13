"""Import the approved native double vine, preserving pixels, timing and pivot."""
from pathlib import Path
from collections import deque
import hashlib
import json
import struct
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/character/朽角巡林者/藤鞭地底重拍_三变体_v2_20261013/03_双藤重拍.aseprite'
DEST = ROOT / 'homeing-star-game/assets/sideview/characters/xiujiao_ranger/human/vfx'
PIVOT = (48, 196)


def body_capsules(image, pivot=PIVOT):
    """Root-connected green silhouette, excluding soil and detached speed marks."""
    pixels = image.load()
    scale = image.width / 224.0
    band = max(6, round(6 * scale))
    remaining = {(x, y) for y in range(image.height) for x in range(image.width)
                 if pixels[x, y][3] >= 128 and pixels[x, y][1] > pixels[x, y][2]
                 and pixels[x, y][1]-pixels[x, y][2] > (pixels[x, y][0]-pixels[x, y][2]) * (2/3)}
    body = set()
    while remaining:
        seed = remaining.pop()
        component = {seed}
        queue = deque([seed])
        while queue:
            x, y = queue.popleft()
            for p in ((x-1, y), (x+1, y), (x, y-1), (x, y+1),
                      (x-1,y-1), (x+1,y-1), (x-1,y+1), (x+1,y+1)):
                if p in remaining:
                    remaining.remove(p)
                    component.add(p)
                    queue.append(p)
        if any(abs(x-pivot[0]) <= 24 * scale and y >= pivot[1]-12 * scale for x, y in component):
            body.update(component)
    capsules = []
    for top in range(0, image.height, band):
        xs = sorted({x for x, y in body if top <= y < top+band})
        if not xs:
            continue
        start = previous = xs[0]
        for x in xs[1:] + [image.width+10]:
            if x > previous+2 * scale:
                y = top+(band-1)*0.5-pivot[1]
                capsules.append([[start-pivot[0], y], [previous-pivot[0], y], band * 0.5])
                start = x
            previous = x
    return capsules


def main():
    raw = SOURCE.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    doc = read(SOURCE)
    assert doc['canvas'] == (224, 224) and len(doc['frames']) == 30
    visible = [i for i, layer in enumerate(doc['layers']) if layer['visible']]
    assert len(visible) == 1
    # Read and verify the authored slice pivot instead of estimating it from pixels.
    position = 144
    pivots = []
    count = struct.unpack_from('<I', raw, 140)[0] or struct.unpack_from('<H', raw, 134)[0]
    for _ in range(count):
        length, kind = struct.unpack_from('<IH', raw, position)
        if kind == 0x2022:
            pivots.append(struct.unpack_from('<ii', raw, position+length-8))
        position += length
    assert PIVOT in pivots, pivots
    frames = []
    sheet = Image.new('RGBA', (224*6, 224*5))
    for i in range(30):
        image, opacity = layer_frame(doc, i, visible[0])
        assert opacity == 1
        frames.append(image)
        sheet.paste(image, ((i % 6)*224, (i // 6)*224))
    data = dict(canvas=[224,224], pivot=list(PIVOT), columns=6, rows=5,
                duration_ms=[f['duration_ms'] for f in doc['frames']],
                active_frames=[11,20], slam_frames=[11,18], impact_frames=[16,18],
                capsules=[body_capsules(im) for im in frames],
                bounds=[im.getbbox() for im in frames], source_sha256=digest)
    DEST.mkdir(parents=True, exist_ok=True)
    sheet.save(DEST / 'vine_ground_lash.png')
    encoded = json.dumps(json.dumps(data, separators=(',', ':')))
    (DEST / 'vine_ground_lash.tres').write_text(
        '[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+encoded+'\n', encoding='utf-8')
    exported = Image.open(DEST / 'vine_ground_lash.png').convert('RGBA')
    for i, image in enumerate(frames):
        x, y = (i % 6)*224, (i // 6)*224
        assert exported.crop((x,y,x+224,y+224)).tobytes() == image.tobytes()
    assert SOURCE.read_bytes() == raw
    print('PASS: 30 native frames copied pixel-exact; original unchanged; pivot (48,196); duration', sum(data['duration_ms']), 'ms')


if __name__ == '__main__':
    main()

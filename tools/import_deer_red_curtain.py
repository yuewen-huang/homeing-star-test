"""Import the four approved red vines unchanged, including timing and slice pivots."""
from pathlib import Path
from collections import deque
import hashlib
import json
import struct
import sys
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'homeing-star-temp-assert/PendingArt/character/朽角巡林者/红藤/Aseprite_20261013'
DEST = ROOT/'homeing-star-game/assets/sideview/characters/xiujiao_ranger/human/vfx'


def pivot_from_slice(raw):
    position = 144
    count = struct.unpack_from('<I', raw, 140)[0] or struct.unpack_from('<H', raw, 134)[0]
    for _ in range(count):
        length, kind = struct.unpack_from('<IH', raw, position)
        if kind == 0x2022:
            body = raw[position+6:position+length]
            keys, flags = struct.unpack_from('<II', body)
            name_length = struct.unpack_from('<H', body, 12)[0]
            name = body[14:14+name_length].decode('utf-8')
            if name == 'vine_origin':
                assert keys == 1 and flags == 2, 'Expected one constant authored pivot'
                return struct.unpack_from('<ii', body, 14+name_length+20)
        position += length
    raise ValueError('Missing authored vine_origin slice; refuse to estimate a pivot')


def body_capsules(image, pivot):
    pixels = image.load()
    remaining = {(x,y) for y in range(image.height) for x in range(image.width) if pixels[x,y][3] >= 128}
    components = []
    while remaining:
        seed = remaining.pop()
        component, queue = {seed}, deque([seed])
        while queue:
            x,y = queue.popleft()
            for point in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if point in remaining:
                    remaining.remove(point); component.add(point); queue.append(point)
        components.append(component)
    body = max(components, key=len) if components else set()
    capsules = []
    for top in range(0, image.height, 8):
        xs = [x for x,y in body if top <= y < top+8]
        if xs:
            capsules.append([[min(xs)-pivot[0], top+3.5-pivot[1]],
                             [max(xs)-pivot[0], top+3.5-pivot[1]], 4.0])
    return capsules


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    clips, snapshots = [], []
    fade_timing = None
    count = None
    DEST.mkdir(parents=True, exist_ok=True)
    for index in range(1,5):
        source = SOURCE/f'{index:02d}_红藤.aseprite'
        raw = source.read_bytes(); snapshots.append((source,raw))
        doc = read(source)
        pivot = pivot_from_slice(raw)
        visible = [i for i,l in enumerate(doc['layers']) if l['visible']]
        assert len(visible) == 1, 'Export only the approved visible effect layer'
        frames = []
        durations = [f['duration_ms'] for f in doc['frames']]
        if count is None: count, fade_timing = len(durations), durations[-3:]
        assert len(durations) == count and count > 3 and durations[-3:] == fade_timing
        width,height = doc['canvas']
        sheet = Image.new('RGBA', (width*7,height*2))
        assert count == 14, 'This approved batch has 14 frames'
        for frame in range(count):
            image, opacity = layer_frame(doc,frame,visible[0])
            assert opacity == 1, 'Do not bake authored layer opacity silently'
            frames.append(image)
            sheet.paste(image,((frame%7)*width,(frame//7)*height))
        filename = f'vine_curtain_{index:02d}.png'
        sheet.save(DEST/filename)
        exported = Image.open(DEST/filename).convert('RGBA')
        for frame,image in enumerate(frames):
            x,y = (frame%7)*width,(frame//7)*height
            assert exported.crop((x,y,x+width,y+height)).tobytes() == image.tobytes()
        clips.append(dict(texture=filename,canvas=list(doc['canvas']),pivot=list(pivot),
                          duration_ms=durations,capsules=[body_capsules(im,pivot) if f<count-3 else [] for f,im in enumerate(frames)],
                          source=source.name,source_sha256=hashlib.sha256(raw).hexdigest()))
        print('PASS',source.name,count,'frames: RGBA, durations, pivot',pivot,'unchanged')
    data = dict(columns=7,frame_count=count,fade_start=count-3,variants=clips)
    encoded = json.dumps(json.dumps(data,separators=(',',':'),ensure_ascii=False),ensure_ascii=False)
    (DEST/'vine_curtain.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+encoded+'\n',encoding='utf-8')
    assert all(source.read_bytes() == raw for source,raw in snapshots)


if __name__ == '__main__': main()

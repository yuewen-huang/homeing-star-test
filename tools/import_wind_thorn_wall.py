"""Export the supplied thorn wall without resizing; verify native PNG pixels against indexed cels."""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib
from PIL import Image


def indexed_frames(path):
    raw = path.read_bytes()
    size, magic, count, width, height, depth = struct.unpack_from('<I5H', raw)
    assert magic == 0xA5E0 and size == len(raw) and depth == 8
    transparent = raw[28]
    palette = [(0, 0, 0, 255)] * 256
    images, durations = [], []
    offset = 128
    for frame in range(count):
        length, magic, chunks, duration = struct.unpack_from('<I3H', raw, offset)
        assert magic == 0xF1FA and duration > 0
        durations.append(duration)
        position = offset + 16
        canvas = Image.new('RGBA', (width, height))
        for _ in range(struct.unpack_from('<I', raw, offset + 12)[0] or chunks):
            chunk_length, kind = struct.unpack_from('<IH', raw, position)
            data = raw[position + 6:position + chunk_length]
            if kind == 0x2019:
                _, first, last = struct.unpack_from('<III', data)
                cursor = 20
                for index in range(first, last + 1):
                    flags = struct.unpack_from('<H', data, cursor)[0]
                    palette[index] = tuple(data[cursor + 2:cursor + 6])
                    cursor += 6
                    if flags & 1:
                        n = struct.unpack_from('<H', data, cursor)[0]
                        cursor += 2 + n
            elif kind == 0x2004:
                flags, layer_type, level, _, _, blend, opacity = struct.unpack_from('<6HB', data)
                assert flags & 1 and layer_type == level == blend == 0 and opacity == 255
            elif kind == 0x2005:
                index, x, y, opacity, cel_type = struct.unpack_from('<HhhBH', data)
                assert index == 0 and opacity == 255 and cel_type in (0, 2)
                w, h = struct.unpack_from('<HH', data, 16)
                pixels = zlib.decompress(data[20:]) if cel_type == 2 else data[20:]
                assert len(pixels) == w * h
                colors = [palette[i] if i != transparent else (0, 0, 0, 0) for i in pixels]
                cel = Image.new('RGBA', (w, h))
                cel.putdata(colors)
                canvas.alpha_composite(cel, (x, y))
            position += chunk_length
        images.append(canvas)
        offset += length
    return images, durations


def main_component_box(image):
    mask = image.getchannel('A')
    pending = {(x, y) for y in range(image.height) for x in range(image.width) if mask.getpixel((x, y)) >= 96}
    largest = []
    while pending:
        first = pending.pop()
        queue, component = deque([first]), [first]
        while queue:
            x, y = queue.popleft()
            for point in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if point in pending:
                    pending.remove(point)
                    queue.append(point)
                    component.append(point)
        if len(component) > len(largest):
            largest = component
    assert largest
    xs, ys = zip(*largest)
    return min(xs), min(ys), max(xs)+1, max(ys)+1


def run(source, project, work, aseprite):
    work.mkdir(parents=True, exist_ok=True)
    images, durations = indexed_frames(source)
    assert len(images) == 6
    png, data = work/'native.png', work/'native.json'
    result = subprocess.run([str(aseprite), '-b', '--list-slices', '--format', 'json-array',
        str(source), '--data', str(data), '--sheet', str(png), '--sheet-type', 'horizontal'],
        capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    assert png.exists() and data.exists(), result.stderr.decode(errors='replace')
    native = json.loads(data.read_text(encoding='utf-8'))
    sheet = Image.open(png).convert('RGBA')
    rows = native['frames']
    assert len(rows) == len(images) and not native['meta'].get('slices')
    boxes = [main_component_box(image) for image in images]
    # Source has no slice pivot: one shared root anchor, never one pivot per frame.
    pivot = [images[0].width / 2, max(box[3] for box in boxes)]
    frames = []
    for image, duration, row, box in zip(images, durations, rows, boxes):
        r = row['frame']
        exported = sheet.crop((r['x'], r['y'], r['x']+r['w'], r['y']+r['h']))
        assert exported.tobytes() == image.tobytes(), 'Native export differs from source pixels'
        assert row['duration'] == duration and not row['trimmed']
        frames.append({'duration_ms': duration, 'region': [r[k] for k in ('x','y','w','h')],
            'hit_rect': [box[0]-pivot[0], box[1]-pivot[1], box[2]-box[0], box[3]-box[1]]})
    target = project/'assets/bosses/deer/fx/wind_thorn_wall'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(png, target/'growth.png')
    animation = {'canvas': list(images[0].size), 'pivot': pivot, 'pivot_source': 'shared root baseline; no source slice',
        'world_scale': 1.4, 'duration_ms': sum(durations), 'frames': frames,
        'source_file': source.name, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
    payload = json.dumps(animation, ensure_ascii=False, separators=(',', ':'))
    (target/'growth.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+json.dumps(payload, ensure_ascii=False)+'\n', encoding='utf-8')
    audit = {'native_exit_code': result.returncode, 'six_frames_verified_pixel_for_pixel': True,
        'durations_ms': durations, 'pivot': pivot, 'source_sha256': animation['source_sha256']}
    (work/'audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding='utf-8')
    # Old native Aseprite can fail at shutdown after a complete export. The independent
    # indexed-cel comparison above is mandatory, even when the native process succeeds.
    print(json.dumps(audit, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('source', 'project', 'work', 'aseprite'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    run(args.source.resolve(), args.project.resolve(), args.work.resolve(), args.aseprite.resolve())

"""Native Aseprite export for RGBA/indexed twin fish, preserving source timing."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/character/双子'
DEST = ROOT / 'homeing-star-game/assets/bosses/twin_fish/body'
AUDIT = ROOT / 'homeing-star-test/artifacts/twin-fish-import'


def source_slices(raw):
    """Record authored slice geometry even when the source uses indexed cels."""
    slices = []
    position = 128
    for _ in range(struct.unpack_from('<H', raw, 6)[0]):
        length, magic, short_count = struct.unpack_from('<IHH', raw, position)
        assert magic == 0xF1FA
        count = struct.unpack_from('<I', raw, position + 12)[0] or short_count
        cursor = position + 16
        for _ in range(count):
            chunk_length, kind = struct.unpack_from('<IH', raw, cursor)
            if kind == 0x2022:
                body = raw[cursor + 6:cursor + chunk_length]
                keys, flags = struct.unpack_from('<II', body)
                n = struct.unpack_from('<H', body, 12)[0]
                name = body[14:14+n].decode('utf-8')
                offset = 14 + n
                entries = []
                for _ in range(keys):
                    frame, x, y, w, h = struct.unpack_from('<IiiII', body, offset)
                    offset += 20
                    entry = dict(frame=frame, bounds=[x, y, w, h])
                    if flags & 1:
                        entry['center'] = list(struct.unpack_from('<iiII', body, offset))
                        offset += 16
                    if flags & 2:
                        px, py = struct.unpack_from('<ii', body, offset)
                        entry['pivot'] = [x + px, y + py]
                        offset += 8
                    entries.append(entry)
                slices.append(dict(name=name, keys=entries))
            cursor += chunk_length
        assert cursor == position + length
        position += length
    assert position == len(raw)
    return slices


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    AUDIT.mkdir(parents=True, exist_ok=True)
    report = []
    for color, filename in [('white', '双子白-walk.aseprite'), ('black', '双子黑-walk.aseprite')]:
        source = SOURCE / filename
        raw = source.read_bytes()
        _, magic, count, width, height, depth = struct.unpack_from('<I5H', raw)
        assert magic == 0xA5E0 and (width, height) == (256, 256) and count == 16
        atlas = DEST / f'twin_{color}_walk.png'
        meta_path = AUDIT / f'{color}_native.json'
        native_run = subprocess.run(['E:/Aseprite/Aseprite.exe', '-b', '--list-layers', '--list-tags',
            str(source), '--format', 'json-array', '--data', str(meta_path), '--sheet', str(atlas),
            '--sheet-type', 'rows', '--sheet-width', '1024'], capture_output=True,
            timeout=45, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        assert native_run.returncode == 0, native_run.stderr
        native = json.loads(meta_path.read_text(encoding='utf-8'))
        image = Image.open(atlas).convert('RGBA')
        image.save(atlas)  # RGBA also for the indexed black source.
        assert image.size == (1024, 1024) and len(native['frames']) == count
        rects, durations = [], []
        for index, frame in enumerate(native['frames']):
            assert not frame['trimmed'] and frame['sourceSize'] == {'w': width, 'h': height}
            rect = frame['frame']
            assert (rect['x'], rect['y'], rect['w'], rect['h']) == (index % 4 * width, index // 4 * height, width, height)
            rects.append([rect['x'], rect['y'], rect['w'], rect['h']])
            durations.append(frame['duration'])
        slices = source_slices(raw)
        pivots = [k['pivot'] for s in slices for k in s['keys'] if 'pivot' in k]
        assert not pivots or all(p == pivots[0] for p in pivots), 'Moving authored pivots require explicit handling'
        pivot = pivots[0] if pivots else [width / 2, height / 2]
        metadata = dict(canvas=[width, height], atlas=list(image.size), frames=rects, duration_ms=durations,
            pivot=pivot, pivot_basis='authored slice' if pivots else 'full-canvas center; no authored pivot',
            source=filename, source_depth=depth, source_sha256=hashlib.sha256(raw).hexdigest(),
            slices=slices, tags=native['meta'].get('frameTags', []), native_aseprite=native['meta']['version'])
        encoded = json.dumps(json.dumps(metadata, ensure_ascii=False, separators=(',', ':')), ensure_ascii=False)
        (DEST / f'twin_{color}_walk.tres').write_text(
            '[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = ' + encoded + '\n', encoding='utf-8')
        assert source.read_bytes() == raw
        report.append(metadata)
        print(f'PASS {color}: {count} unchanged native frames; {durations}; pivot {pivot}; source depth {depth}', flush=True)
    (AUDIT / 'import_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()

"""Read-only native export and contact sheets for the user's simplified deer."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path('C:/Users/P6063166/Downloads/简化')
OUT = ROOT / 'homeing-star-test/artifacts/deer-authored-20261105'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = {}
    for source in sorted(SOURCE.glob('*.aseprite')):
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        sheet = OUT / (source.stem + '.png')
        metadata = OUT / (source.stem + '.json')
        subprocess.run([
            'E:/Aseprite/Aseprite.exe', '-b', str(source), '--list-tags',
            '--list-slices', '--format', 'json-array', '--data', str(metadata),
            '--sheet', str(sheet), '--sheet-type', 'horizontal',
        ], check=True, capture_output=True, timeout=60,
            env=dict(os.environ, APPDATA=str(OUT / 'aseprite-profile')),
            creationflags=subprocess.CREATE_NO_WINDOW)
        data = json.loads(metadata.read_text(encoding='utf-8'))
        atlas = Image.open(sheet).convert('RGBA')
        frames = []
        bboxes = []
        w, h = data['frames'][0]['sourceSize'].values()
        board = Image.new('RGBA', (w * 5, (h + 24) * ((len(data['frames']) + 4) // 5)), '#293038')
        draw = ImageDraw.Draw(board)
        for i, entry in enumerate(data['frames']):
            r = entry['frame']
            frame = atlas.crop((r['x'], r['y'], r['x'] + r['w'], r['y'] + r['h']))
            bboxes.append(frame.getbbox())
            x, y = (i % 5) * w, (i // 5) * (h + 24)
            board.alpha_composite(frame, (x, y + 24))
            draw.text((x + 5, y + 5), f'{i:02} / {entry["duration"]} ms', fill='white')
            draw.line((x, y + h + 23, x + w - 1, y + h + 23), fill='#626a75')
            preview = Image.new('RGBA', (w, h), '#293038')
            preview.alpha_composite(frame)
            frames.append(preview.convert('RGB'))
        board.save(OUT / (source.stem + '_contact.png'))
        frames[0].save(OUT / (source.stem + '_preview.gif'), save_all=True,
                       append_images=frames[1:], duration=[e['duration'] for e in data['frames']], loop=0)
        assert digest == hashlib.sha256(source.read_bytes()).hexdigest()
        results[source.name] = dict(count=len(frames), canvas=[w, h],
            durations_ms=[e['duration'] for e in data['frames']],
            tags=data['meta'].get('frameTags', []), slices=data['meta'].get('slices', []),
            source_sha256=digest, bboxes=bboxes)
    (OUT / 'audit.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()

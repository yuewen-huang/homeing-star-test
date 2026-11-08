"""Repair reviewed alpha holes only. No AI, interpolation, resize, or opaque edits.

Default prepares immutable backups, repaired originals, and review sheets.
--apply synchronizes reviewed outputs to Downloads and the editor; run the normal
production importer afterwards. Re-running is safe and checks source hashes.
"""
from pathlib import Path
from collections import defaultdict
import argparse
import hashlib
import json
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'smear-combo-demo/characters/sandstorm_fighter'
ARCHIVE = ROOT / 'homeing-star-temp-assert/ProductionArt/chapter_3/sandstorm_fighter/20261107_chest_repair'
DOWNLOADS = Path('D:/DownLoad')
MASK = Path(__file__).with_name('sandstorm_chest_repairs.json')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(MASK.read_text(encoding='utf-8'))
    for name in ['before', 'repaired', 'review']:
        (ARCHIVE / name).mkdir(parents=True, exist_ok=True)
    grouped = defaultdict(list)
    for repair in manifest['repairs']:
        grouped[repair['file']].append(repair)
    report = {'method': manifest['description'], 'files': [], 'pixels': 0, 'frames': 0}
    reviews = []
    for filename, repairs in grouped.items():
        original = SOURCE / filename
        before = ARCHIVE / 'before' / filename
        if not before.exists():
            assert sha(original) == manifest['source_sha256'][filename], f'Source changed: {filename}'
            shutil.copyfile(original, before)
        assert sha(before) == manifest['source_sha256'][filename], f'Backup changed: {filename}'
        im = Image.open(before).convert('RGBA')
        old = np.array(im)
        new = old.copy()
        mask = np.zeros(old.shape[:2], dtype=bool)
        frames = set()
        for repair in repairs:
            frame, columns = repair['frame'], repair['columns']
            frames.add(frame)
            ox, oy = frame % columns * 256, frame // columns * 256
            for x, y, r, g, b, a in repair['pixels']:
                assert old[oy+y, ox+x, 3] == 0, (filename, frame, x, y)
                new[oy+y, ox+x] = (r, g, b, a)
                mask[oy+y, ox+x] = True
        assert np.array_equal(old[~mask], new[~mask]), 'A non-mask pixel changed'
        assert np.array_equal(old[old[:, :, 3] > 0], new[old[:, :, 3] > 0]), 'Opaque art changed'
        fixed = Image.fromarray(new)
        assert im.getbbox() == fixed.getbbox(), 'Sheet silhouette changed'
        columns = repairs[0]['columns']
        for frame in frames:
            x, y = frame % columns * 256, frame // columns * 256
            region = (x, y, x+256, y+256)
            assert im.crop(region).getbbox() == fixed.crop(region).getbbox(), 'Frame anchor changed'
            pixels = [p for r in repairs if r['frame'] == frame for p in r['pixels']]
            min_x, max_x = min(p[0] for p in pixels), max(p[0] for p in pixels)
            min_y, max_y = min(p[1] for p in pixels), max(p[1] for p in pixels)
            cx, cy = (min_x+max_x)//2, (min_y+max_y)//2
            crop = (x+cx-20, y+cy-20, x+cx+20, y+cy+20)
            reviews.append((f"{repairs[0]['action']} F{frame}", im.crop(crop), fixed.crop(crop)))
        output = ARCHIVE / 'repaired' / filename
        fixed.save(output)
        report['files'].append({'file': filename, 'before_sha256': sha(before), 'after_sha256': sha(output),
                                'frames': sorted(frames), 'pixels': int(mask.sum())})
        report['pixels'] += int(mask.sum())
        report['frames'] += len(frames)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 14)
    for page in range((len(reviews)+19)//20):
        canvas = Image.new('RGB', (1280, 5*188), '#303034')
        draw = ImageDraw.Draw(canvas)
        for i, (label, old, new) in enumerate(reviews[page*20:(page+1)*20]):
            x, y = i % 4 * 320, i // 4 * 188
            draw.text((x+3, y), label+'  前 / 后', font=font, fill='white')
            for side, image in enumerate([old, new]):
                bg = Image.new('RGBA', image.size, '#28b5b5')
                bg.alpha_composite(image)
                canvas.paste(bg.resize((160,160), Image.Resampling.NEAREST), (x+160*side,y+24))
        canvas.save(ARCHIVE / 'review' / f'comparison_{page:02}.png')
    shutil.copyfile(MASK, ARCHIVE / MASK.name)
    (ARCHIVE / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    if args.apply:
        # Preflight every target before any source mutation; do not overwrite later user edits.
        for item in report['files']:
            for folder in (SOURCE, DOWNLOADS):
                assert sha(folder / item['file']) in (item['before_sha256'], item['after_sha256']), f'New user edit: {folder / item["file"]}'
        for item in report['files']:
            for folder in (SOURCE, DOWNLOADS):
                shutil.copyfile(ARCHIVE / 'repaired' / item['file'], folder / item['file'])
        source_manifest_path = SOURCE / 'import_manifest.json'
        backup = ARCHIVE / 'source_import_manifest_before.json'
        if not backup.exists(): shutil.copyfile(source_manifest_path, backup)
        source_manifest = json.loads(source_manifest_path.read_text(encoding='utf-8'))
        for action in source_manifest['actions']:
            file = SOURCE / (action['name']+'.png')
            if file.name in grouped: action['sha256'] = sha(file)
        source_manifest['chest_alpha_repair'] = 'ProductionArt/chapter_3/sandstorm_fighter/20261107_chest_repair/report.json'
        source_manifest_path.write_text(json.dumps(source_manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f"{'APPLIED' if args.apply else 'PREPARED'}: {len(report['files'])} sheets, {report['frames']} frames, {report['pixels']} transparent pixels repaired; opaque pixels and frame bounds unchanged")

if __name__ == '__main__':
    main()

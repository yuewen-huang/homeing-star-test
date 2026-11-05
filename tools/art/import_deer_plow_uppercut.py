"""Native export of the user's plowing uppercut; no repainting or normalization."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'homeing-star-test/artifacts/deer-plow-uppercut-20261105'
DEST = ROOT / 'homeing-star-game/assets/bosses/deer/body/plow_uppercut'
ARCHIVE = ROOT / 'homeing-star-temp-assert/ProductionArt/deer_redesign/20261105/user_authored'
# Inclusive, zero-based; source has no tags. These are observed motion phases,
# not attack timing or hit windows. Run and lift are independently addressable.
SEGMENTS = {'plow_START': (0, 9), 'plow_ING': (10, 17),
            'plow_lift_ING': (18, 22), 'plow_END': (23, 31)}
# Body/antler registration measured on the native pixel grid. Horizontal root
# travel is removed in combat only; canvas preview still shows the raw motion.
ROOT_X = [112,112,112,112,112,94,94,94,94,94,96,102,108,114,126,138,150,162,158,135,112,110,106,104,108,112,112,112,112,112,112,112]
CHEST = [(143,207),(143,207),(143,207),(146,208),(155,216),(128,222),(128,222),(128,222),(129,222),(129,222),
         (137,222),(143,222),(149,222),(155,222),(167,222),(179,222),(191,222),(203,222),
         (210,208),(179,203),(163,183),(161,181),(154,181),(150,182),(148,186),(143,195),
         (150,212),(149,210),(145,207),(143,207),(143,207),(143,207)]
HORN_BASE = [(151,164)]*5 + [(145,222)]*5 + [(148,222),(154,222),(160,222),(166,222),(178,222),(190,222),(202,222),(214,222),
             (218,205),(183,183),(155,141),(150,136),(145,137)] + [(143,144)]*9
HORN_TIP = [(174,140)]*5 + [(194,247)]*5 + [(200,247),(206,247),(212,247),(218,247),(230,247),(242,247),(253,247),(254,247),
            (250,220),(220,190),(185,139),(180,134),(174,135)] + [(172,145)]*9


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('D:/DownLoad/lidi_chongci_shangtiao.aseprite'))
    parser.add_argument('--aseprite', default='D:/Aseprite/Aseprite.exe')
    args = parser.parse_args()
    original = args.source.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run([args.aseprite, '-b', str(args.source), '--list-tags', '--list-slices',
                    '--format', 'json-array', '--data', str(OUT / 'source.json'),
                    '--sheet', str(OUT / 'source.png'), '--sheet-type', 'horizontal'],
                   check=True, capture_output=True, timeout=60,
                   env=dict(os.environ, APPDATA=str(OUT / 'aseprite-profile')),
                   creationflags=subprocess.CREATE_NO_WINDOW)
    data = json.loads((OUT / 'source.json').read_text(encoding='utf8'))
    frames = data['frames']
    assert len(frames) == 32, 'Source changed: review motion stages again'
    assert all(e['sourceSize'] == {'w': 256, 'h': 256} and not e['trimmed'] and not e['rotated'] for e in frames)
    atlas = Image.open(OUT / 'source.png').convert('RGBA')
    cells = []
    for entry in frames:
        r = entry['frame']
        cells.append(atlas.crop((r['x'], r['y'], r['x'] + r['w'], r['y'] + r['h'])))
    DEST.mkdir(parents=True, exist_ok=True)
    clips = {}
    for name, (first, last) in SEGMENTS.items():
        sheet = Image.new('RGBA', ((last-first+1)*256, 256))
        for local, frame in enumerate(range(first, last+1)):
            sheet.paste(cells[frame], (local*256, 0))
        sheet.save(DEST / (name + '.png'))
        saved = Image.open(DEST / (name + '.png')).convert('RGBA')
        for local, frame in enumerate(range(first, last+1)):
            assert saved.crop((local*256, 0, (local+1)*256, 256)).tobytes() == cells[frame].tobytes()
        clips[name] = dict(file=name+'.png', count=last-first+1,
                           source_frames=list(range(first, last+1)),
                           durations_ms=[frames[f]['duration'] for f in range(first, last+1)],
                           roots=[[ROOT_X[f],256] for f in range(first,last+1)],
                           chest=CHEST[first:last+1], horn_base=HORN_BASE[first:last+1], horn_tip=HORN_TIP[first:last+1])
    manifest = dict(source=args.source.name, source_sha256=digest, frame_size=[256, 256],
                    canvas_pivot=[112, 256], world_scale=1.75, clips=clips)
    (DEST / 'clips.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf8')
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    backup = ARCHIVE / args.source.name
    if backup.exists() and backup.read_bytes() != original:
        raise RuntimeError('A different source is already archived; do not overwrite')
    shutil.copyfile(args.source, backup)
    assert args.source.read_bytes() == backup.read_bytes() == original
    board = Image.new('RGBA', (1280, 7*280), '#293038')
    draw = ImageDraw.Draw(board)
    for i, cell in enumerate(cells):
        x, y = i % 5 * 256, i // 5 * 280
        board.alpha_composite(cell, (x, y+24))
        draw.text((x+5, y+5), f'F{i+1:02} / {frames[i]["duration"]}ms', fill='white')
    board.save(OUT / 'contact.png')
    audit = dict(manifest, duration_ms=sum(e['duration'] for e in frames),
                 tags=data['meta'].get('frameTags', []), slices=data['meta'].get('slices', []),
                 bboxes=[cell.getbbox() for cell in cells], rgba_verified_frames=len(cells),
                 note='Native canvas travel retained in source preview; combat root motion is not authored here.')
    (ARCHIVE / 'plow_uppercut_audit.json').write_text(json.dumps(audit, indent=2)+'\n', encoding='utf8')
    print(f'4 physical clips, 32 RGBA-identical frames, {audit["duration_ms"]} ms; source and archive SHA256 {digest}')


if __name__ == '__main__':
    main()

"""Join the authored deer base-action segments without remapping their pixels."""
from pathlib import Path
import hashlib
import json
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'homeing-star-game/assets/bosses/deer/body/boss/actions'
OUTPUT = ROOT / '拼刀编辑/鹿'
sys.path.insert(0, str(ROOT / 'smear-combo-demo/tools'))
from aseprite_reader import Sprite
from package_master_phase1_aseprite import write_document

# Original animation families, not the game's composite moves or substituted recoveries.
MOVES = {
    '01_角刺_thrust': ['thrust_START', 'thrust_ING', 'thrust_END'],
    '02_红色角击_rear_gore': ['rear_gore_START', 'rear_gore_ING', 'rear_gore_END'],
    '03_甩头挑击_flick': ['flick_START', 'flick_ING', 'flick_END'],
    '04_角力前进_bind_push': ['bind_push_START', 'bind_push_ING'],
    '05_人立践踏_heavy': ['heavy_START', 'heavy_ING', 'heavy_END'],
    '06_冲刺上挑_charge': ['charge_START', 'charge_ING', 'charge_END'],
    '07_待机_idle': ['idle_ING'],
    '08_行走_walk': ['walk_ING'],
}

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    targets = [OUTPUT / (name + '.aseprite') for name in MOVES]
    existing = [p for p in targets if p.exists()]
    if existing:
        raise SystemExit('Refusing to overwrite existing files: ' + ', '.join(map(str, existing)))
    report = []
    for (name, clips), path in zip(MOVES.items(), targets):
        images, durations, records = [], [], []
        for clip in clips:
            source = SOURCE / (clip + '.aseprite')
            sprite = Sprite(source)
            assert not sprite.warnings and (sprite.width, sprite.height) == (200, 200)
            first = len(images)
            for i, frame in enumerate(sprite.frames):
                images.append(sprite.composite(i, lambda layer: layer['shown']))
                durations.append(frame['duration'])
            records.append({'clip': clip, 'frames': [first, len(images)-1],
                            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
        write_document(path, images, durations, 'action')
        result = Sprite(path)
        assert len(result.frames) == len(images) and not result.warnings
        for i, image in enumerate(images):
            assert result.composite(i, lambda layer: layer['shown']).tobytes() == image.tobytes()
            assert result.frames[i]['duration'] == durations[i]
        report.append({'file': path.name, 'frames': len(images), 'durations_ms': durations, 'segments': records})
        print(f'{path.name}: {len(images)} frames; ' + ', '.join(clips))
    (OUTPUT / '动作来源与帧区间.json').write_text(json.dumps({'canvas': [200, 200],
        'note': 'User-edited Aseprite source segments joined in source order without moving, resizing, or recoloring pixels; source durations retained.',
        'moves': report}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    main()

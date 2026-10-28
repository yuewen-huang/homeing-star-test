"""Import completed deer annotations and only the strike renderer dependencies."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
DEMO = ROOT / 'smear-combo-demo'
GAME = ROOT / 'homeing-star-game'
SCRIPTS = 'scripts/bosses/deer/studio_vfx/'
ASSETS = 'assets/bosses/deer/fx/studio/'

def main():
    bridge = json.loads((DEMO / '.local-data/deer_phase3_bridge.json').read_text(encoding='utf-8-sig'))
    raw = DEMO / 'characters/deer_phase3/character.json'
    digest = hashlib.sha256(raw.read_bytes()).hexdigest()
    metadata = json.loads((ROOT / '拼刀编辑/鹿/动作来源与帧区间.json').read_text(encoding='utf-8'))
    sources = {row['file']: row for row in metadata['moves']}
    character = json.loads(raw.read_text(encoding='utf-8'))
    library = json.loads((GAME / 'assets/bosses/deer/body/boss/actions/library.json').read_text(encoding='utf-8'))['clips']
    moves = {}
    for combo in bridge['combos']:
        assert combo['source_sha256'] == digest
        cursor, clips, events = 0.0, [], []
        for clip in combo['clips']:
            source = sources[character['actions'][clip['action']]['source'].split('#')[0]]
            segments = []
            for segment in source['segments']:
                path = GAME / ('assets/bosses/deer/body/boss/actions/' + segment['clip'] + '.aseprite')
                assert hashlib.sha256(path.read_bytes()).hexdigest() == segment['source_sha256'], 'Source changed: ' + str(path)
                segments.append(dict(clip=segment['clip'], first=segment['frames'][0], last=segment['frames'][1]))
            first = library[segments[0]['clip']]
            pivot = [n / first['texture_to_logical_scale'] for n in first['pivot']]
            durations = character['actions'][clip['action']]['durations']
            clips.append(dict(begin=cursor, duration=clip['duration'], source_from=clip['start_time'], segments=segments,
                              durations_ms=durations, label=clip['label']))
            for event in clip['events']:
                out = {k: v for k, v in event.items() if k != 'collision_samples'}
                for key in ['wind', 'release', 'contact', 'end', 'fade_end']:
                    out[key] += cursor - clip['start_time']
                out['pivot'] = pivot
                out['danger'] = 1 if clip['action'].startswith(('02_', '05_')) else 0
                out['launch'] = -180.0 if clip['action'].startswith(('03_', '06_')) else 0.0
                events.append(out)
            cursor += clip['duration']
        moves[combo['id']] = dict(title=combo['title'], body_duration=cursor, clips=clips, events=events)
    output = dict(version=1, source_sha256=digest, native_scale=1.792, heavy_radius=320.0, moves=moves)
    target = GAME / 'assets/bosses/deer/fx/phase3'
    target.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(output, ensure_ascii=False, indent=2)
    (target / 'arrangements.json').write_text(encoded + '\n', encoding='utf-8')
    (target / 'arrangements.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/data = ' + json.dumps(encoded, ensure_ascii=False) + '\n', encoding='utf-8')
    pending = ['track_strike.gd']
    seen = set()
    pattern = re.compile(r'res://vfx/([\w./-]+\.(?:gdshaderinc|gdshader|gd))')
    def mapped(path):
        return (SCRIPTS if path.endswith('.gd') else ASSETS) + path.removeprefix('vendor_studio/')
    while pending:
        path = pending.pop()
        if path in seen: continue
        seen.add(path)
        text = (DEMO / 'vfx' / path).read_text(encoding='utf-8-sig')
        if path == 'effect_curve.gd':
            text = text[:text.index('## First draft for a cut')]
        pending.extend(pattern.findall(text))
        text = pattern.sub(lambda m: 'res://' + mapped(m[1]), text)
        text = text.replace('res://vfx/vendor_studio/magic/shaders/', 'res://' + ASSETS + 'magic/shaders/')
        if 'RenderCaps.' in text:
            text = text.replace('extends Node2D', 'extends Node2D\nconst RenderCaps = preload("res://scripts/bosses/master/studio_vfx/render_caps.gd")', 1)
        dest = GAME / mapped(path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text, encoding='utf-8')
    assert hashlib.sha256(raw.read_bytes()).hexdigest() == digest
    print(f'PASS imported {len(moves)} deer combos and {len(seen)} strike renderer dependencies; heavy radius 320')

if __name__ == '__main__':
    main()

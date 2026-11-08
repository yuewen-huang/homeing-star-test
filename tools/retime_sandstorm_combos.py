"""Retiming production frame boundaries, keeping source art/annotations/anchors intact.

Every root key and explicit contact follows its original source-frame fraction.
Run once against the captured before snapshot; repeat runs remain deterministic.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'homeing-star-game'
BACKUP = ROOT / 'homeing-star-test/artifacts/sandstorm-rhythm/baseline_code'
FILES = [
    'scripts/bosses/sandstorm_fighter/sandstorm_melee.gd',
    'scripts/bosses/sandstorm_fighter/sandstorm_ambush.gd',
    'scripts/bosses/sandstorm_fighter/sandstorm_descent.gd',
    'scripts/bosses/sandstorm_fighter/sandstorm_thomas.gd',
    'scripts/bosses/sandstorm_fighter/authored/arranged_track_player.gd',
    'scripts/bosses/sandstorm_fighter/authored/library_data.gd',
    'assets/bosses/sandstorm_fighter/data/thomas_skill.json',
] + [f'assets/bosses/sandstorm_fighter/data/sandstorm_{n}.json' for n in ['pressure', 'counter']]
for name in FILES:
    dst = BACKUP / name
    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((GAME / name).read_bytes())

common = {
    '野蛮冲撞': (3, [28, 24, 24, 28, 32, 44]),
    '摆拳': (3, [25, 20, 22, 22, 35, 38]),
    '肘击': (5, [28, 22, 24, 35, 40]),
    '膝击': (4, [32, 24, 28, 45]),
    '升龙拳': (2, [45, 45, 115, 28, 28, 32, 34, 40, 45]),
}
profiles = {
    'pressure': {
        '刺拳': (4, [100, 22, 26, 42]),
        '凌空抽射': (4, [45, 22, 24, 65]),
        '后空翻': (4, [30, 30, 35, 50, 65, 40, 30, 30]),
        '断头台': (4, [80, 24, 24, 45, 30, 115, 70, 55, 55, 70]),
    },
    'counter': {
        '后空翻': (1, [70, 65, 38, 30, 30, 35, 55, 60, 38, 30, 30, 42, 80]),
        '刺踢': (2, [80, 25, 28, 60]),
        '侧身斜上踢': (2, [150, 24, 26, 28, 100, 50, 45, 45, 45, 45, 45, 45, 70, 70]),
    },
}

def remap(t, old, new):
    start_old = start_new = 0.0
    for a, b in zip(old, new):
        a /= 1000
        b /= 1000
        if t < start_old + a - 1e-8:
            return round(start_new + (t-start_old)*b/a, 8)
        start_old += a
        start_new += b
    return round(start_new + t-start_old, 8)

def sample(keys, t):
    for left, right in zip(keys, keys[1:]):
        if t <= right[0]:
            u = max(0, min(1, (t-left[0])/max(.000001,right[0]-left[0])))
            return [left[j]+(right[j]-left[j])*u for j in [1,2]]
    return keys[-1][1:]

bundled = {}
report = []
for name, specific in profiles.items():
    rel = f'assets/bosses/sandstorm_fighter/data/sandstorm_{name}.json'
    original = json.loads((BACKUP/rel).read_text(encoding='utf8'))
    data = json.loads(json.dumps(original))
    for action, (first, durations) in (common | specific).items():
        data['frame_durations'][action][first:first+len(durations)] = durations
    duration = 0.0
    for entry in data['actions']:
        action = entry['action']
        old = original['frame_durations'][action]
        new = data['frame_durations'][action]
        entry['start_time'] = remap(entry['start_time'], old, new)
        for keys in entry.get('motion', {}).values():
            for key in keys:
                key[0] = remap(key[0], old, new)
        for key, value in entry.get('contact_overrides', {}).items():
            # These contacts were solved against the wind's curved path, rather
            # than a frame boundary. Preserve that path share after retiming.
            track = next(t for t in data['annotation_tracks'] if t['kind']=='strike')
            swing = [int(k.rsplit(':',1)[1]) for k,v in track['roles'].items()
                     if k.startswith(action+':') and v in ('swing','finish')]
            if swing:
                begin_old = sum(old[:min(swing)])/1000
                end_old = sum(old[:max(swing)+1])/1000
                begin_new = sum(new[:min(swing)])/1000
                end_new = sum(new[:max(swing)+1])/1000
                share = (value-begin_old)/(end_old-begin_old)
                entry['contact_overrides'][key] = round(begin_new+share*(end_new-begin_new),8)
            else:
                entry['contact_overrides'][key] = remap(value, old, new)
        if action == '伏虎霸王拳':
            # F7 is the planted ground strike; the raised fist in F6 cannot hit.
            entry['contact_overrides']['0'] = round(sum(new[:6])/1000+.010, 8)
            entry['event_end_overrides'] = {'0': round(begin_new+(entry['contact_overrides']['0']-begin_new)/share,8)}
        # The editor's virtual receiver rises with a launcher. Keep its position
        # at each authored contact when that contact moves within the new swing.
        prior = next(e for e in original['actions'] if e['action']==action)
        if 'target_roots' in entry.get('motion', {}):
            for key, old_contact in prior.get('contact_overrides', {}).items():
                contact = entry['contact_overrides'][key]
                point = sample(prior['motion']['target_roots'], old_contact)
                keys = entry['motion']['target_roots']
                keys[:] = [p for p in keys if abs(p[0]-contact)>.000001]
                keys.append([contact, *point])
                keys.sort(key=lambda p:p[0])
        end = sum(new[:entry.get('handoff_frame', len(new))])/1000
        duration += end-entry['start_time']
    assert data['annotation_tracks'] == original['annotation_tracks']
    assert data['transition_ghosts'] is True
    text = json.dumps(data, ensure_ascii=False, indent='\t')+'\n'
    (GAME/rel).write_text(text, encoding='utf8')
    bundled['sandstorm_'+name] = text
    report.append({'combo': name, 'body_duration': round(duration, 6)})

path = GAME/'scripts/bosses/sandstorm_fighter/authored/library_data.gd'
lines = (BACKUP/'scripts/bosses/sandstorm_fighter/authored/library_data.gd').read_text(encoding='utf8').splitlines()
lines = [line for line in lines if not line.startswith('\t"sandstorm_breaker":')]
for i, line in enumerate(lines):
    for key, value in bundled.items():
        if line.startswith('\t"'+key+'":'):
            lines[i] = '\t'+json.dumps(key)+': '+json.dumps(value, ensure_ascii=False)+','
path.write_text('\n'.join(lines)+'\n', encoding='utf8')
(BACKUP.parent/'combo_timing.json').write_text(json.dumps(report, indent=2), encoding='utf8')
print(json.dumps(report))

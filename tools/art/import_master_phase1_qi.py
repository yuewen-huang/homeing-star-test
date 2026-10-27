"""Snapshot saved Studio sword-qi presets without modifying the editor's documents."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / 'homeing-star-game/assets/bosses/master/fx/phase1/sword_qi_profiles.json'
SOURCES = {
    'mountain': ('quake_sword_flame', 'crescent'),
    'hinge': ('greatblade_hinge', 'greatblade'),
    'plunge': ('greatblade_guillotine', 'greatblade'),
}


def main():
    profiles = {}
    for role, (name, form) in SOURCES.items():
        folder = ROOT / 'combat-vfx-studio/combos' / name
        raw = (folder / 'combo.json').read_bytes()
        raw_style = (folder / 'style.json').read_bytes()
        document = json.loads(raw.decode('utf-8-sig'))
        events = [e for e in document['events'] if e.get('do') == 'quake']
        if len(events) != 1 or events[0].get('form') != form:
            raise SystemExit(f'{name}: expected one saved {form} quake event')
        event = events[0]
        style = json.loads(raw_style.decode('utf-8-sig'))
        style.update(event.get('_flow_style', {}))
        profiles[role] = {
            'source': f'combos/{name}',
            'combo_sha256': hashlib.sha256(raw).hexdigest(),
            'style_sha256': hashlib.sha256(raw_style).hexdigest(),
            'style': style,
            'event': {k: v for k, v in event.items()
                      if not k.startswith('_') and k not in ('t', 'x', 'y', 'do')},
        }
        if (folder / 'combo.json').read_bytes() != raw:
            raise SystemExit(f'{name} changed during export; save and rerun')
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text(json.dumps({'version': 1, 'profiles': profiles},
                              ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Imported saved mountain, hinge and plunge presets; Studio files unchanged.')


if __name__ == '__main__':
    main()

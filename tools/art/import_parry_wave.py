"""Import saved Studio parry looks and their renderer into the game's shared VFX."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
STUDIO = ROOT / 'combat-vfx-studio'
GAME = ROOT / 'homeing-star-game'
SCRIPTS = 'scripts/vfx/studio_parry/'
SHADERS = 'assets/shared/shaders/studio_parry/'


def main():
    hashes = {}
    for name in ['parry_wave.gd', 'render_caps.gd', 'parry_wave.gdshader',
                 'parry_wave_lite.gdshader', 'parry_vignette.gdshader']:
        raw = (STUDIO / 'vfx' / name).read_bytes()
        hashes[name] = hashlib.sha256(raw).hexdigest()
        source = raw.decode('utf-8-sig').replace('\r\n', '\n')
        source = re.sub(r'^class_name \w+\s*\n', '', source, flags=re.M)
        if name == 'parry_wave.gd':
            source = source.replace('extends Node2D\n', 'extends Node2D\n'
                                    f'const RenderCaps = preload("res://{SCRIPTS}render_caps.gd")\n', 1)
            source = source.replace('blade_tilt := NAN) -> ParryWave:',
                                    'blade_tilt := NAN, screen_pulse := true) -> Node2D:')
            source = source.replace('\tif bool(spec.red):\n\t\t# The game',
                                    '\tif bool(spec.red) and screen_pulse:\n\t\t# The game')
            for shader in ['parry_wave.gdshader', 'parry_wave_lite.gdshader', 'parry_vignette.gdshader']:
                source = source.replace('res://vfx/' + shader, 'res://' + SHADERS + shader)
        dest = GAME / (SCRIPTS if name.endswith('.gd') else SHADERS) / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(source, encoding='utf-8')
    documents = {}
    profiles = {}
    for name in ['parry_wave', 'parry_chain']:
        path = STUDIO / 'combos' / name / 'combo.json'
        raw = path.read_bytes()
        documents[name] = hashlib.sha256(raw).hexdigest()
        profiles[name] = [e for e in json.loads(raw.decode('utf-8-sig'))['events']
                          if e.get('do') == 'parry']
    normal = profiles['parry_wave']
    chain = [e for e in profiles['parry_chain'] if not e.get('red', False)]
    red = [e for e in profiles['parry_chain'] if e.get('red', False)]
    if not normal or not chain or not red:
        raise SystemExit('Saved ordinary, chain and red parry events are required')
    clean = lambda e: {k: v for k, v in e.items()
                       if k not in ['t', 'do', 'at'] and not k.startswith('_')}
    dest = GAME / 'assets/shared/combat_fx/parry_wave/profile.json'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps({'version': 1, 'sources': hashes, 'documents': documents,
                               'normal': clean(normal[0]), 'chain': [clean(e) for e in chain],
                               'red': clean(red[-1])}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Imported ordinary, chain and red parry profiles plus the shared lens renderer.')


if __name__ == '__main__':
    main()

"""Import the Studio's actual brush + normal/钢蓝 result, without changing source art."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'combat-vfx-studio/vfx'
DEST = ROOT / 'homeing-star-game/assets/bosses/master/fx/phase1'


def main():
    look = (SOURCE / 'blade_look.gd').read_text(encoding='utf-8-sig')
    match = re.search(r'const MASTER := \[([^\]]+)\]', look)
    if not match:
        raise SystemExit('Studio brush MASTER colour table missing; review the source contract.')
    colours = re.findall(r'Color\("([0-9a-fA-F]{6})"\)', match[1])
    if len(colours) != 4:
        raise SystemExit('Expected four actual brush inks, brightest first.')
    DEST.mkdir(parents=True, exist_ok=True)
    shader = (SOURCE / 'brush_trail.gdshader').read_bytes()
    (DEST / 'brush_trail.gdshader').write_bytes(shader)
    data = {
        'blade_style': 'brush', 'editor_palette': 'normal', 'editor_palette_label': '钢蓝',
        'resolved_palette': 'BladeLook.MASTER', 'inks': colours,
        'sources': {name: hashlib.sha256((SOURCE/name).read_bytes()).hexdigest()
                    for name in ['blade_look.gd', 'brush_trail.gdshader']},
    }
    (DEST / 'palette.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('Imported Studio brush + 钢蓝 resolved inks:', ', '.join(colours))


if __name__ == '__main__':
    main()

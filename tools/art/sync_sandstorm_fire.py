"""Vendor the Studio pressure renderer and authored recipes; no sibling runtime reads."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
STUDIO = ROOT / 'combat-vfx-studio'
GAME = ROOT / 'homeing-star-game'
DEST = GAME / 'assets/bosses/sandstorm_fighter/fx/fire'
DEST.mkdir(parents=True, exist_ok=True)
manifest = {}
for source in sorted((STUDIO / 'vfx/unarmed').glob('pressure_*')):
    if source.suffix not in ('.gd', '.gdshader', '.gdshaderinc') or source.name == 'pressure_lens.gdshader':
        continue
    content = source.read_text(encoding='utf-8')
    content = content.replace('res://vfx/unarmed/', 'res://assets/bosses/sandstorm_fighter/fx/fire/')
    content = content.replace('res://vfx/magic/magic_art.gd', 'res://assets/bosses/sandstorm_fighter/fx/fire/magic_art.gd')
    (DEST / source.name).write_text(content, encoding='utf-8')
    manifest[source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
art = STUDIO / 'vfx/magic/magic_art.gd'
(DEST / 'magic_art.gd').write_bytes(art.read_bytes())
manifest['magic_art.gd'] = hashlib.sha256(art.read_bytes()).hexdigest()
recipes = {}
for folder in sorted((STUDIO / 'combos').glob('sandstorm_fire_*')):
    recipe = json.loads((folder / 'combo.json').read_text(encoding='utf-8'))
    recipes[recipe['binding']['action']] = recipe
    for filename in ('combo.json', 'style.json', 'prompt.md'):
        (DEST / (folder.name + '_' + filename)).write_bytes((folder / filename).read_bytes())
(DEST / 'recipes.json').write_text(json.dumps(recipes, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(DEST / 'source_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
(DEST / 'SOURCE.md').write_text('# 蝎女炎劲\n\n来源：combat-vfx-studio/combos/sandstorm_fire_*。\n通过 homeing-star-test/tools/art/sync_sandstorm_fire.py 同步原生程序渲染器与配方；正式游戏只读本目录。\n动作接点与时钟由 sandstorm_fire_strike.gd 绑定。pressure_core.gd 与渲染器共享主轴几何，正式战斗由 sandstorm_fire_hitbox.gd 结算明亮核心；散焰、螺旋与火星不判伤。\n', encoding='utf-8')
print(f'Synced {len(recipes)} distinct fire recipes and {len(manifest)} renderer sources')

"""Port the studio's actual tornado drawing; remove only demo-stage behavior.

Preserve the volume, helices, dust, leaf shapes, flow shader and seeded variation.
The production MasterSwordQi owns collision, travel and pause, never the studio dummy.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'combat-vfx-studio/vfx/magic'
GAME = ROOT / 'homeing-star-game'
SCRIPTS = GAME / 'scripts/bosses/master/studio_vfx/wind'
ASSETS = GAME / 'assets/bosses/master/fx/phase1/wind'
SCRIPTS.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
script_root = 'res://scripts/bosses/master/studio_vfx/wind/'
asset_root = 'res://assets/bosses/master/fx/phase1/wind/'
sources = {}

def read(relative):
    path = SOURCE / relative
    sources[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return path.read_text(encoding='utf-8')

art = read('magic_art.gd').replace('res://vfx/magic/shaders/', asset_root)
(SCRIPTS / 'magic_art.gd').write_text(art, encoding='utf-8')
arcs = read('thunder/arcs.gd').replace('res://vfx/magic/magic_art.gd', script_root + 'magic_art.gd')
(SCRIPTS / 'arcs.gd').write_text(arcs, encoding='utf-8')
gusts = read('wind/gusts.gd').replace('res://vfx/magic/magic_art.gd', script_root + 'magic_art.gd').replace('res://vfx/magic/thunder/arcs.gd', script_root + 'arcs.gd')
gusts = gusts.replace('extends RefCounted', 'extends RefCounted\nconst RenderCaps = preload("res://scripts/bosses/master/studio_vfx/render_caps.gd")', 1)
# Dry leaves belong to the grounded greatsword palette, not a green spell.
gusts = gusts.replace('Color(0.35, 0.7, 0.28).lerp(Color(0.85, 0.78, 0.3), k)', 'Color(0.42, 0.43, 0.38).lerp(Color(0.67, 0.63, 0.48), k)')
(SCRIPTS / 'gusts.gd').write_text(gusts, encoding='utf-8')
for name in ['wind.gdshader', 'noise.gdshaderinc']:
    text = read('shaders/' + name).replace('res://vfx/magic/shaders/', asset_root)
    if name == 'wind.gdshader':
        text = text.replace('vec3(0.96, 0.99, 1.0)', 'vec3(0.94, 0.96, 0.93)')
    (ASSETS / name).write_text(text, encoding='utf-8')

body = read('wind/tornado.gd')
# Keep the real template geometry below the imports, replacing its stage-bound base.
body = body[body.index('## Funnel height'):body.index('## What it carries, mixed in:')]
body = body.replace('var _carried: Canvas\n', '')
body = body.replace('\tsuper._ready()\n', '')
body = body.replace('\t_x = start_point(0).x\n', '\t_x = 0.0\n')
body = body.replace('\tlife = _end() + BURST + 0.6', '\tlife = _end() + BURST')
body = body.replace('Gusts.node(float(seed_id % 13))', 'Gusts.node(float(seed_id % 13), false)')
body = body.replace('\tif materials.size() > 1:\n\t\t_carried = Canvas.new()\n\t\tadd_child(_carried)\n', '')
body = body.replace('\tsuper.advance(delta)', '\tage += maxf(0.0, delta)')
start = body.index('\tif age < stop and age > charge * 0.6:')
end = body.index('\t_debris(', start)
body = body[:start] + body[end:]
body = '\n'.join(line for line in body.split('\n') if 'if _carried != null:' not in line)
body = body.replace('func _update() -> void:\n', 'func _update() -> void:\n\t_x = minf(age, 1.30) * 320.0\n')
body = body.replace('size = _size * lerpf(1.0, swell, clampf(age / maxf(stop, 0.01), 0.0, 1.0))', 'size = growth_size(age)')
body = body.replace('return _x + sway * up *', 'return _x + h * 0.38 + sway * up *')
header = f'''extends Node2D
## Imported studio tornado drawing; see tools/art/import_master_tornado.py.
## Deliberate adaptations: local floor, forward-growing tilted travel, dry leaves,
## bone-white wind tint, no stage suction or elemental mixing. Geometry is preserved.
const Art = preload("{script_root}magic_art.gd")
const Gusts = preload("{script_root}gusts.gd")
const GROUND_Y := 0.0
var age := 0.0
var life := 1.85
var size := 0.72
var seed_id := 17
var charge := 0.16
var count := 1
func growth_size(time: float) -> float:
    return 0.72 * lerpf(0.38, 1.35, smoothstep(0.0, 1.30, time))
func collision_points(time: float) -> PackedVector2Array:
    # Same growing, forward-leaning core as the drawn funnel; wisps are cosmetic.
    var amount := growth_size(time)
    var height := 340.0 * amount * (0.25 + 0.75 * ease_out(time / charge))
    var points := PackedVector2Array()
    for side: float in [-1.0, 1.0]:
        for j in 7:
            var u := j / 7.0 if side < 0 else (6 - j) / 7.0
            var h := height * u
            var r := (22.0 + 125.0 * pow(u, 1.4)) * amount * 0.65
            points.append(Vector2(minf(time, 1.30) * 320.0 + h * 0.38 + side * r, -h - 5.0))
    return points
func land(_i: int) -> float: return 1.30
func is_done() -> bool: return age >= life
func rnd(k: int) -> float:
    var v := sin(float(k * 131 + seed_id * 7919) * 0.0137 + 78.233) * 43758.5453
    return v - floorf(v)
func rnd2(k: int) -> float: return rnd(k) * 2.0 - 1.0
func ease_out(x: float, p := 2.0) -> float: return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), p)
'''
(GAME / 'scripts/bosses/master/master_tornado_wind.gd').write_text(header.replace('    ', '\t') + '\n' + body, encoding='utf-8')
(ASSETS / 'studio_sources.json').write_text(json.dumps(sources, indent=2) + '\n', encoding='utf-8')
print('Ported original studio tornado geometry, volume and flow shader')

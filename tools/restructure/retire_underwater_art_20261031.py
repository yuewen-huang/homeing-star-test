"""One-shot retirement authorized by the user; preserves the approved city far image."""
from pathlib import Path
import json
import re
import shutil
import move_res_paths as mover

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'homeing-star-game'
TEST = ROOT / 'homeing-star-test'
NAME = 'underwater-art-retired-20261031'
ARCHIVE = ROOT / 'homeing-star-temp-assert/Archive/game-unused-20261019' / NAME
KEEP = 'assets/levels/chapter_2_underwater/city/environment/sunken_port_far_2172x724.png'


def edit(rel, transform):
    path = GAME / rel
    original = path.read_text(encoding='utf-8')
    backup = ARCHIVE / 'source-before-cleanup' / rel
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_text(original, encoding='utf-8')
    path.write_text(transform(original), encoding='utf-8')


def remove_function(text, name):
    return re.sub(r'^func ' + name + r'\([^\n]*\n.*?(?=^func |\Z)', '', text, flags=re.M | re.S)


def legacy(text):
    text = text.replace('\t_build_room_art()\n', '').replace('\t_build_hud()\n', '')
    text = text[:text.index('\telif "--r08-art-demo"')] + text[text.index('\n\nfunc marker_position'):]
    start = text.index('## Art pass:')
    text = text[:start] + text[text.index('func _build_markers()', start):]
    # The old artwork hid these labels. Do not reveal them when removing art.
    text = re.sub(r'\t\tvar label := Label.new\(\).*?\t\tfill.add_child\(label\)\n', '', text, flags=re.S)
    text = re.sub(r'\t\tvar label := Label.new\(\).*?\t\tmarker.add_child\(label\)\n', '', text, flags=re.S)
    return text


def tower(text):
    text = text.replace('## Painted architectural components share the verified collision/water coordinates.',
                        '## Retired art removed: this scene retains only gameplay graybox geometry.')
    text = re.sub(r'^const (PANEL_SCRIPT|ART_SCRIPT|WATER_CLIP) :=.*\n', '', text, flags=re.M)
    text = re.sub(r'^var (panels|architecture_art|_gate_art|_latch_handle|_middle_gate_art|_middle_latch_handle|_upper_gate_art|_upper_latch_handle)\b.*\n', '', text, flags=re.M)
    text = text.replace('\t_build_facades()\n', '').replace('\t_build_art()\n', '')
    text = text.replace('\t_update_facades(0.0, true)\n', '').replace('\t_update_facades(delta)\n', '')
    for name in ['_build_art', '_build_latch_art', '_make_middle_latch', '_panel', '_build_facades', '_stair_panel', '_update_facades']:
        text = remove_function(text, name)
    # Water registration and all collision rects stay unchanged; the art mask is retired.
    start = text.index('\tvar mask := Image.create')
    text = text[:start] + text[text.index('\tfor rect in WATER_RECTS:', start):]
    text = text.replace('\t\tvolume.material = material\n', '')
    for field in ['_gate_art', '_middle_gate_art', '_upper_gate_art']:
        text = re.sub(r'\t' + field + r' = Sprite2D.new\(\).*?(?=\n\nfunc )', '', text, flags=re.S)
    text = re.sub(r'^\t_(?:gate_art|middle_gate_art|upper_gate_art)\.visible = false\n', '', text, flags=re.M)
    text = re.sub(r'^\t_(?:latch_handle|middle_latch_handle|upper_latch_handle)\.rotation = 0.65\n', '', text, flags=re.M)
    text = text.replace('func _process(delta: float)', 'func _process(_delta: float)')
    text = text.replace('\tmiddle_shortcut_opened.emit()\n', '\tmiddle_shortcut_opened.emit()\n\tqueue_redraw()\n')
    text = text.replace('\tupper_shortcut_opened.emit()\n', '\tupper_shortcut_opened.emit()\n\tqueue_redraw()\n')
    text += '''func _draw() -> void:
\t# Plain gameplay placeholders only. No retired architecture or textures.
\tfor entry in [[GATE_RECT, shortcut_is_open], [MIDDLE_GATE_RECT, middle_shortcut_is_open], [UPPER_GATE_RECT, upper_shortcut_is_open]]:
\t\tif not entry[1]: draw_rect(entry[0], Color(0.30, 0.35, 0.38))
\tfor at in [LATCH, MIDDLE_LATCH, UPPER_LATCH]:
\t\tdraw_circle(at + Vector2(0, -22), 12, Color(0.48, 0.51, 0.53))
'''
    return text


def city(text):
    text = text.replace('## First city segment only. Explicit rectangles are shared by physics and art.',
                        '## First city graybox. All rejected gate art has been retired.')
    text = re.sub(r'^const PAINT :=.*$', 'const FAR := preload("res://' + KEEP + '")', text, flags=re.M)
    text = text.replace('\t_terrain.visible = false', '\t_terrain.visible = true')
    text = text.replace('\tif is_instance_valid(camera): PAINT.paint(self,camera.get_screen_center_position())', '''\tif not is_instance_valid(camera): return
\tvar focus := camera.get_screen_center_position()
\tvar origin := focus - Vector2(640, 360)
\tdraw_texture_rect(FAR, Rect2(origin + Vector2(-(focus.x - 640) * 0.10, -20), Vector2(2280, 760)), false, Color(0.88, 0.94, 0.93))''')
    return text


def main():
    if ARCHIVE.exists():
        raise SystemExit('Refusing to overwrite an existing retirement archive')
    keep_bytes = (GAME / KEEP).read_bytes()
    edit('scripts/levels/chapter_2_underwater/chapter_2_underwater.gd', legacy)
    edit('scripts/levels/chapter_2_underwater/tower/underwater_tower_foundation.gd', tower)
    edit('scripts/levels/chapter_2_underwater/city/sunken_city_gate.gd', city)
    asset_root = GAME / 'assets/levels/chapter_2_underwater'
    assets = [p for p in asset_root.rglob('*') if p.is_file() and p.suffix not in {'.import', '.uid'} and p.relative_to(GAME).as_posix() != KEEP]
    scripts_root = GAME / 'scripts/levels/chapter_2_underwater'
    scripts = list(scripts_root.glob('*_art_demo.gd')) + [scripts_root / 'chapter_2_underwater_room_art.gd']
    scripts += [scripts_root / 'tower' / f for f in ['tower_architecture_art.gd', 'tower_architecture_geometry.gd', 'tower_dressing.gd', 'tower_facade_panel.gd']]
    scripts += [scripts_root / 'city/city_gate_art.gd']
    scripts += list(GAME.glob('_patch_batch*.py'))
    paths = [p.relative_to(GAME).as_posix() for p in assets + scripts]
    code = mover.main(['--root', str(ROOT), '--archive-name', NAME, '--apply'] + [part for rel in paths for part in ['--archive-unused', rel]])
    if code: raise SystemExit(code)
    # Retire restore/import tools and art-specific captures together with their dependencies.
    tools = list((TEST / 'tools/level_design').glob('capture_tower_*.gd'))
    tools += [TEST / rel for rel in ['tools/art/prepare_tower_dressing.py', 'tools/art/soften_underwater_tower.py', 'tests/levels/chapter_2_underwater/tower/test_tower_dressing_paths.gd']]
    for source in tools:
        target = ARCHIVE / 'homeing-star-test' / source.relative_to(TEST)
        assert source.resolve().is_relative_to(TEST.resolve()) and target.resolve().is_relative_to(ARCHIVE.resolve())
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(target))
    for test in (TEST / 'tests/levels/chapter_2_underwater/tower').glob('test_underwater_tower_*.gd'):
        text = test.read_text(encoding='utf-8')
        text = '\n'.join(line for line in text.split('\n') if 'check(level.panels[' not in line)
        test.write_text(text, encoding='utf-8')
    assert (GAME / KEEP).read_bytes() == keep_bytes
    remaining = [p.relative_to(GAME).as_posix() for p in asset_root.rglob('*') if p.is_file()]
    assert sorted(remaining) == sorted([KEEP, KEEP + '.import']), remaining
    report = {'retired_pngs': sum(p.suffix == '.png' for p in assets), 'retired_shaders': sum(p.suffix == '.gdshader' for p in assets), 'retired_game_files': len(paths), 'retired_test_tools': len(tools), 'kept': KEEP}
    (ARCHIVE / 'retirement.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (ARCHIVE / 'README.md').write_text('# Retired underwater map art\n\nUser rejected all legacy, tower and gate trial art on 2026-10-31. These files are historical evidence only. Do not restore, reimport, copy or reuse them without a new explicit user request. The approved city far background remains in the game. Gameplay scenes remain grayboxes.\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

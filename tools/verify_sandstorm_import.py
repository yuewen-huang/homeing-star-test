"""Verify the production import against the editor's current approved repertoire."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[2]
game = root / 'homeing-star-game'
source = root / 'smear-combo-demo'
data = game / 'assets/bosses/sandstorm_fighter/data'
manifest = json.loads((data / 'import_manifest.json').read_text(encoding='utf-8'))
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
character_path = source / 'characters/sandstorm_fighter/character.json'
assert sha(character_path) == manifest['character_sha256']
expected = json.loads(character_path.read_text(encoding='utf-8'))
expected['name'] = '第三章 · 蝎女'
assert json.loads((data / 'character.json').read_text(encoding='utf-8')) == expected
assert manifest['frame_count'] == 269 and len(manifest['assets']) == 17
for item in manifest['assets']:
    assert sha(game / item['path']) == sha(character_path.parent / item['source']) == item['sha256']
assert set(manifest['combos']) == {'sandstorm_pressure', 'sandstorm_counter'}
for key, item in manifest['combos'].items():
    original = source / 'combos' / key / 'combo.json'
    assert sha(data / f'{key}.json') == sha(original) == item['sha256']
    plan = json.loads(original.read_text(encoding='utf-8'))
    assert plan['transition_ghosts'] and plan['hit_stop'] == 0.018
for directory in ('scripts/bosses/sandstorm_fighter', 'assets/bosses/sandstorm_fighter'):
    for path in (game / directory).rglob('*.gd'):
        text = path.read_text(encoding='utf-8')
        assert 'res://../' not in text and 'D:/HomingStar' not in text, path
print('PASS: 17 byte-identical atlases / 269 frames; 2 byte-identical combo files; annotations intact; game-local runtime')

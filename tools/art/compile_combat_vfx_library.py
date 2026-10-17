"""Compile the baked JSON index into a Godot Resource with explicit texture dependencies.

The .tres keeps every atlas reachable in exported builds, without adjacent-repo sources.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
assets = ROOT / 'homeing-star-game/assets/sideview/effects/combat_baked'
manifest = json.loads((assets / 'manifest.json').read_text(encoding='utf-8'))
pages = sorted({page for clip in manifest['clips'].values() for page in clip['pages']})
lines = [f'[gd_resource type="Resource" load_steps={len(pages) + 1} format=3]', '']
for i, page in enumerate(pages, 1):
    lines.append(f'[ext_resource type="Texture2D" path="res://assets/sideview/effects/combat_baked/{page}" id="{i}"]')
lines += ['', '[resource]', 'metadata/manifest = ' + json.dumps(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')), ensure_ascii=False), 'metadata/textures = {']
lines += [json.dumps(page) + f': ExtResource("{i}")' + (',' if i < len(pages) else '') for i, page in enumerate(pages, 1)]
lines += ['}', '']
(assets / 'library.tres').write_text('\n'.join(lines), encoding='utf-8')
print(f'Compiled {len(manifest["clips"])} clips, {len(pages)} texture dependencies')

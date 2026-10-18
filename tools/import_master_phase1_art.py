"""Export the approved indexed Aseprite art without resizing or editing sources."""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/character/师傅优化计划'
DEST = ROOT / 'homeing-star-game/assets/sideview/characters/master/boss/phase1_refined'
AUDIT = ROOT / '.artifacts/master-phase1-audit/native'
CONFIG = {
    'idle': ('phase1_optimized_idle_16f', 256, True),
    'walk_start': ('phase1_optimized_walk_start_11f', 256, False),
    'walk': ('phase1_optimized_walking_loop_10f', 320, True),
    'drink': ('phase1_optimized_drink_16f', 256, False),
    'hurt': ('phase1_optimized_weak_16f', 256, False),
    'attack_1': ('phase1_optimized_atak1_body_16f', 675, False),
    'attack_2': ('phase1_optimized_atak2_body_25f', 750, False),
    'attack_3': ('phase1_optimized_atak3_body_32f', 600, False),
    'dash': ('phase1_optimized_shunyi_body_16f', 600, False),
    'special_attack': ('phase1_optimized_sp_atak_body_16f', 500, False),
    'air_spin_slam': ('起跳空中旋斩下劈', 0, False),
}

# Audited source-frame ranges, inclusive and zero-based. Single-role source
# loops/start motions do not acquire invented parts. Composite attacks retain
# explicit internal strikes for later effect-driven rhythm composition.
PARTS = {
    'idle': {'ING': [0,15]}, 'walk_start': {'START': [0,10]}, 'walk': {'ING': [0,9]},
    'drink': {'START': [0,3], 'ING': [4,11], 'END': [12,15]},
    'hurt': {'START': [0,3], 'ING': [4,11], 'END': [12,15]},
    'attack_1': {'START': [0,6], 'ING': [7,10], 'END': [11,15]},
    'attack_2': {'START': [0,6], 'ING': [7,21], 'END': [22,24]},
    'attack_3': {'START': [0,4], 'ING': [5,18], 'END': [19,31]},
    'dash': {'START': [0,4], 'ING': [5,10], 'END': [11,15]},
    'special_attack': {'START': [0,8], 'ING': [9,13], 'END': [14,15]},
    'air_spin_slam': {'START': [0,5], 'ING': [6,23], 'END': [24,29]},
}
SUBMOVES = {
    'attack_2_return': {'source': 'attack_2', 'label': '攻击二 · 回身扫', 'parts': {'START':[11,13], 'ING':[14,16]}},
    'attack_2_reverse': {'source': 'attack_2', 'label': '攻击二 · 翻身斩', 'parts': {'START':[17,19], 'ING':[20,21], 'END':[22,24]}},
    'attack_3_spin': {'source': 'attack_3', 'label': '旋风 · 横旋', 'parts': {'START':[8,9], 'ING':[10,12]}},
    'attack_3_lift': {'source': 'attack_3', 'label': '旋风 · 挑斩', 'parts': {'START':[13,16], 'ING':[17,18], 'END':[19,31]}},
    'air_spin': {'source': 'air_spin_slam', 'label': '空中 · 旋斩', 'parts': {'START':[6,7], 'ING':[8,15]}},
    'air_slam': {'source': 'air_spin_slam', 'label': '空中 · 下劈落地', 'parts': {'START':[16,16], 'ING':[17,23], 'END':[24,29]}},
    'attack_2_open': {'source': 'attack_2', 'label': '攻击二 · 首刀', 'parts': {'START':[0,6], 'ING':[7,10]}},
    'attack_3_down': {'source': 'attack_3', 'label': '旋风 · 前斩', 'parts': {'START':[0,4], 'ING':[5,7]}},
}

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    AUDIT.mkdir(parents=True, exist_ok=True)
    manifest = {'source': str(SOURCE), 'actions': {}, 'submoves': SUBMOVES}
    ext, sub, animations = [], [], []
    for action, (stem, old_width, loop) in CONFIG.items():
        source = SOURCE / (stem + '.aseprite')
        native, data = AUDIT / (action + '.png'), AUDIT / (action + '.json')
        native.unlink(missing_ok=True)
        data.unlink(missing_ok=True)
        result = subprocess.run(['D:/Aseprite/Aseprite.exe', '-b', str(source),
            '--list-tags', '--list-slices', '--format', 'json-array', '--data', str(data),
            '--sheet', str(native), '--sheet-type', 'horizontal'], capture_output=True,
            timeout=45, creationflags=subprocess.CREATE_NO_WINDOW)
        # This installed native exporter can return a nonzero status after saving.
        if not native.exists() or not data.exists():
            raise RuntimeError(result.stderr.decode(errors='replace'))
        meta = json.loads(data.read_text(encoding='utf8'))
        source_image = Image.open(native).convert('RGBA')
        records = meta['frames']
        w, h = records[0]['sourceSize']['w'], records[0]['sourceSize']['h']
        native_frames = []
        for i, frame in enumerate(records):
            rect = frame['frame']
            native_frames.append(source_image.crop((rect['x'], rect['y'], rect['x']+w, rect['y']+h)))
        def export_move(move, parts, whole_loop=False):
            all_entries = []
            for part, (first, last) in parts.items():
                clip = move + '_' + part
                columns = min(4, last-first+1)
                atlas = Image.new('RGBA', (w*columns, h*((last-first+columns)//columns)))
                entries = []
                for local, i in enumerate(range(first, last+1)):
                    x,y = local%columns*w, local//columns*h
                    atlas.paste(native_frames[i], (x,y))
                    ident = f'{clip}_{local}'
                    sub.append(f'[sub_resource type="AtlasTexture" id="{ident}"]\natlas = ExtResource("{clip}")\nregion = Rect2({x}, {y}, {w}, {h})\n')
                    entries.append('{"duration": %s, "texture": SubResource("%s")}' % (records[i]['duration']/1000, ident))
                path = DEST / 'actions' / (clip+'.png')
                path.parent.mkdir(parents=True, exist_ok=True)
                atlas.save(path)
                saved = Image.open(path).convert('RGBA')
                for local,i in enumerate(range(first,last+1)):
                    x,y = local%columns*w, local//columns*h
                    assert saved.crop((x,y,x+w,y+h)).tobytes() == native_frames[i].tobytes(), (clip,i)
                ext.append(f'[ext_resource type="Texture2D" path="res://assets/sideview/characters/master/boss/phase1_refined/actions/{clip}.png" id="{clip}"]\n')
                animations.append('{"frames": [%s], "loop": false, "name": &"%s", "speed": 1.0}' % (', '.join(entries), clip))
                all_entries.extend(entries)
            animations.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": 1.0}' % (', '.join(all_entries), str(whole_loop).lower(), move))
        assert [i for a,b in PARTS[action].values() for i in range(a,b+1)] == list(range(len(records)))
        export_move(action, PARTS[action], loop)
        for move, spec in SUBMOVES.items():
            if spec['source'] == action: export_move(move, spec['parts'])
        manifest['actions'][action] = {'source': source.name, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'frame_size': [w, h], 'frame_count': len(records),
            'durations_ms': [f['duration'] for f in records], 'tags': meta['meta']['frameTags'],
            'slices': meta['meta']['slices'], 'parts': PARTS[action],
            'body_scale_compensation': old_width/w if old_width else 5/3}
    (DEST / 'frames.tres').write_text('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n' % (len(ext)+len(sub)+1)
        + '\n'.join(ext + sub) + '\n[resource]\nanimations = [' + ',\n'.join(animations) + ']\n', encoding='utf8')
    (DEST / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    # Explicitly named obsolete generated atlases only; source documents stay intact.
    for action in CONFIG:
        (DEST/(action+'.png')).unlink(missing_ok=True)
        (DEST/(action+'.png.import')).unlink(missing_ok=True)
    generated = ['class_name MasterPhase1Segments','extends RefCounted','', 'const PARTS := '+json.dumps(PARTS, ensure_ascii=False), 'const SUBMOVES := '+json.dumps(SUBMOVES, ensure_ascii=False), '']
    (ROOT/'homeing-star-game/scripts/sideview/master_phase1_segments.gd').write_text('\n'.join(generated),encoding='utf8')
    print(f'Verified independent action segments and {len(SUBMOVES)} compound submoves:', DEST)

if __name__ == '__main__':
    main()

"""Copy only the reviewed new master moves into a self-contained production pack."""
from pathlib import Path
import json, hashlib, shutil
import sys
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from aseprite_rgba_reader import read, layer_frame
from normalize_master_action import normalize

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'smear-combo-demo'
GAME = ROOT / 'homeing-star-game'
DEST = GAME / 'assets/bosses/master/body/boss/phase1/skills'
ACTION_IDS = {
    '上挑接失衡': 'rise_unbalance', '横斩': 'horizontal', '竖劈': 'vertical',
    '崩山击': 'mountain', '脑瓜崩': 'finger_flick', '飞剑': 'peanut_sword',
    '06_攻击一_attack_1_attack_1': 'opening_slash',
    '07_攻击二_attack_2_attack_2': 'return_slash',
    'shanbi': 'dodge',
}
MOVES = {
    'rise_unbalance': ('master_skill_rise_unbalance', '上挑接失衡'),
    'horizontal': ('master_skill_horizontal', '横斩'),
    'vertical': ('master_skill_vertical', '竖劈'),
    'mountain': ('master_skill_mountain', '崩山击'),
    'combo_three': ('master_small_three', '三刀连招'),
    'combo_four': ('master_small_four', '四刀连招'),
    'combo_five': ('master_small_five', '五刀连招'),
}

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    character_path = SOURCE / 'characters/master_phase1_new/character.json'
    raw = json.loads(character_path.read_text(encoding='utf-8'))
    # Body-only animation: preserve the authored canvas/timing and the same fixed
    # registration as the other 400x256 master actions. No per-frame root motion.
    dodge_path = ROOT / '角色Aseprite/师傅一阶段/新动作/shanbi.aseprite'
    dodge = read(dodge_path)
    assert dodge['canvas'] == (400, 256), 'Review registration if the authored canvas changes'
    columns = min(8, len(dodge['frames']))
    sheet = Image.new('RGBA', (400 * columns, 256 * ((len(dodge['frames']) + columns - 1) // columns)))
    for i in range(len(dodge['frames'])):
        frame = Image.new('RGBA', dodge['canvas'])
        for index, layer in enumerate(dodge['layers']):
            if not layer['visible']: continue
            pixels, opacity = layer_frame(dodge, i, index)
            if opacity != 1.0: pixels.putalpha(pixels.getchannel('A').point(lambda a: round(a * opacity)))
            frame = Image.alpha_composite(frame, pixels)
        sheet.paste(frame, ((i % columns) * 400, (i // columns) * 256))
    dodge_sheet = DEST / 'dodge.png'
    sheet.save(dodge_sheet)
    raw['actions']['shanbi'] = {'cell': [400,256], 'feet': [186,256], 'facing': 'right',
        'durations': [f['duration_ms'] for f in dodge['frames']],
        'sheets': [{'file':'dodge.png', 'columns':columns, 'count':len(dodge['frames'])}],
        '_sheet_source': dodge_sheet}
    phase1 = GAME / 'assets/bosses/master/body/boss/phase1'
    idle_spec = json.loads((phase1/'manifest.json').read_text(encoding='utf-8'))['actions']['idle']
    iw,ih = idle_spec['frame_size']
    idle = Image.open(phase1/'actions/idle_ING.png').convert('RGBA').crop((0,0,iw,ih))
    world_scale = idle_spec['body_scale_compensation']
    data = {'scale': world_scale, 'actions': {}, 'poses': {}, 'moves': {},
            'mechanisms': {'finger_flick': '脑瓜崩', 'peanut_sword': '吃花生飞剑', 'dodge': '闪避 · 仅动画'},
            'source_sha256': hashlib.sha256(character_path.read_bytes()).hexdigest()}
    resources, animations = [], []
    transforms = {}
    for name, key in ACTION_IDS.items():
        spec = raw['actions'][name]
        assert len(spec['sheets']) == 1, 'Review exporter before supporting multiple source sheets'
        sheet = spec['sheets'][0]
        src = spec.get('_sheet_source', character_path.parent / sheet['file'])
        filename = key + '.png'
        source_hash = hashlib.sha256(src.read_bytes()).hexdigest()
        source_image = Image.open(src).convert('RGBA')
        sw,sh = map(int,spec['cell']); source_columns=int(sheet['columns'])
        originals = [source_image.crop(((i%source_columns)*sw,(i//source_columns)*sh,
                       (i%source_columns+1)*sw,(i//source_columns+1)*sh)) for i in range(int(sheet['count']))]
        normalized,feet,report = normalize(originals,idle,world_scale)
        w,h = normalized[0].size
        columns = min(8,len(normalized))
        atlas_image = Image.new('RGBA',(w*columns,h*((len(normalized)+columns-1)//columns)))
        for i,frame in enumerate(normalized):atlas_image.paste(frame,((i%columns)*w,(i//columns)*h))
        atlas_image.save(DEST/filename)
        transforms[key] = report
        data['actions'][key] = {'cell':[w,h], 'feet':feet, 'durations':spec['durations'],
            'scale':1.0, 'facing':spec.get('facing',raw.get('facing','right')),
            'sha256':hashlib.sha256((DEST/filename).read_bytes()).hexdigest(),
            'source_sheet_sha256':source_hash, 'normalization':report}
        if key == 'dodge':
            data['actions'][key]['source_aseprite_sha256'] = hashlib.sha256(dodge_path.read_bytes()).hexdigest()
        resources.append(f'[ext_resource type="Texture2D" path="res://assets/bosses/master/body/boss/phase1/skills/{filename}" id="{key}"]')
        frames = []
        for i in range(int(sheet['count'])):
            atlas = f'{key}_{i}'
            resources.append(f'[sub_resource type="AtlasTexture" id="{atlas}"]\natlas = ExtResource("{key}")\nregion = Rect2({i%columns*w}, {i//columns*h}, {w}, {h})')
            frames.append('{"duration": '+str(spec['durations'][i]/100)+', "texture": SubResource("'+atlas+'")}')
        animations.append('{"name": &"skill_'+key+'", "loop": false, "speed": 10.0, "frames": ['+',\n'.join(frames)+']}')
    for key, pose in raw['poses'].items():
        name,frame = key.rsplit(':',1)
        if name in ACTION_IDS:
            key=ACTION_IDS[name];transform=transforms[key];factor=transform['pixel_scale'];left,top=transform['crop_origin']
            data['poses'][key+':'+frame]={part:[point[0]*factor-left,point[1]*factor-top] for part,point in pose.items()}
    for key,(folder,label) in MOVES.items():
        combo = json.loads((SOURCE/'combos'/folder/'combo.json').read_text(encoding='utf-8'))
        for cut in combo['cuts']:
            assert cut['action'] in ACTION_IDS
            cut['action'] = ACTION_IDS[cut['action']]
            cut['look'] = 'trail'
            factor = transforms[cut['action']]['pixel_scale']
            if 'frame_offsets' in cut:
                cut['frame_offsets']={frame:[v*factor for v in offset] for frame,offset in cut['frame_offsets'].items()}
        combo['look'] = 'trail'
        combo.pop('character',None)
        data['moves'][key] = {'label':label, 'source_combo':folder, 'combo':combo}
    (DEST/'action_pack.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    ext=[x for x in resources if x.startswith('[ext_resource')]
    sub=[x for x in resources if x.startswith('[sub_resource')]
    (DEST/'frames.tres').write_text('[gd_resource type="SpriteFrames" load_steps='+str(len(resources)+1)+' format=3]\n\n'+'\n\n'.join(ext+sub)+'\n\n[resource]\nanimations = ['+',\n'.join(animations)+']\n',encoding='utf-8')
    # The imported timeline/ribbon method is MIT licensed; keep its notice with the pack.
    shutil.copy2(SOURCE/'LICENSE',DEST/'smear_method_license.txt')
    print(f'Exported {len(ACTION_IDS)} body actions, {len(MOVES)} moves; whirlwind excluded')
    for key,action in data['actions'].items():
        print(f"{key}: cell={action['cell']}, body={action['normalization']['rendered_body_height']:.2f} world px, feet={action['feet']}")

if __name__ == '__main__':main()

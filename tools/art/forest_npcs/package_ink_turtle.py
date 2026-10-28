"""Mechanically package sprite-pipeline's eight normalized turtle frames."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/forest_npcs/20261029-ink_turtle'
DEST = ROOT / 'homeing-star-game/assets/characters/ink_turtle/body'
DEST.mkdir(parents=True, exist_ok=True)
frames = []
for i in range(1, 9):
    src = Image.open(SOURCE / 'normalized' / f'{i:02d}.png').convert('RGBA')
    assert src.size == (256, 256)
    # One shared scale for all frames, with visible feet at (64,152).
    scaled = src.resize((143, 143), Image.Resampling.LANCZOS)
    frame = Image.new('RGBA', (128, 160))
    frame.alpha_composite(scaled, ((128 - 143) // 2, 10))
    bbox = frame.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    assert bbox and bbox[0] > 0 and bbox[2] < 128 and bbox[3] == 153, bbox
    frames.append(frame)

for name, start in [('idle', 0), ('talk', 4)]:
    sheet = Image.new('RGBA', (512, 160))
    for i in range(4): sheet.alpha_composite(frames[start+i], (i*128, 0))
    sheet.save(DEST / f'{name}_128x160_4f.png')

text = '[gd_resource type="SpriteFrames" load_steps=11 format=3]\n\n'
for i, name in enumerate(['idle', 'talk'], 1):
    text += f'[ext_resource type="Texture2D" path="res://assets/characters/ink_turtle/body/{name}_128x160_4f.png" id="{i}"]\n\n'
for j in range(8):
    text += f'[sub_resource type="AtlasTexture" id="Frame_{j}"]\natlas = ExtResource("{j//4+1}")\nregion = Rect2({j%4*128}, 0, 128, 160)\n\n'
text += '[resource]\nanimations = [\n'
for name, start, speed, durations in [('idle',0,3.0,[6.0,1.0,0.35,1.0]),('talk',4,5.0,[1.0,1.0,1.0,1.5])]:
    entries = ', '.join('{"duration": %s, "texture": SubResource("Frame_%d")}' % (d,start+i) for i,d in enumerate(durations))
    text += '{"frames": ['+entries+'], "loop": true, "name": &"'+name+'", "speed": '+str(speed)+'},\n'
text += ']\n'
(DEST/'animations.tres').write_text(text, encoding='utf-8')
metadata = dict(id='ink_turtle', name='龟先生', species='anthropomorphic_turtle', frame_size=[128,160],
    feet_anchor=[64,152], default_draw_scale=0.70, facing='left',
    animations={'idle':dict(frames=4,fps=3.0,durations=[6.0,1.0,0.35,1.0]),
                'talk':dict(frames=4,fps=5.0,durations=[1.0,1.0,1.0,1.5])},
    normalization='sprite-pipeline shared scale, bottom-center; all eight frames resized by 143/256',
    source='homeing-star-temp-assert/PendingArt/forest_npcs/20261029-ink_turtle',
    scope='Animation asset only. Dialogue and mirror-lake trial integration deferred by user.')
(DEST.parent/'art_metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
preview_dir=SOURCE/'runtime_frames'
preview_dir.mkdir(exist_ok=True)
for i,f in enumerate(frames): f.save(preview_dir/f'{i+1:02d}.png')
for name, start, durations in [('idle',0,[2000,333,117,333]),('talk',4,[200,200,200,300])]:
    views=[]
    for frame in frames[start:start+4]:
        bg=Image.new('RGBA',frame.size,(232,227,214,255)); bg.alpha_composite(frame)
        views.append(bg.resize((256,320),Image.Resampling.NEAREST).convert('RGB'))
    views[0].save(SOURCE/f'{name}_preview.gif',save_all=True,append_images=views[1:],duration=durations,loop=0,disposal=2)
print('Packaged idle and talk, shared feet anchor (64,152), draw scale 0.70')

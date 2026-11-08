"""Editable Studio recipe and source foot contacts for the Thomas sand waves."""
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'homeing-star-game'
FOLDER = ROOT / 'combat-vfx-studio/combos/sandstorm_thomas_wave'
FOLDER.mkdir(parents=True, exist_ok=True)
base = dict(t=0, do='swarm', material='sand', form='stream', at=[640,520],
            size=.95, sand_grain=.65, sand_dust=0, sand_settle=0,
            look='mirror', ramp=['33261c','705239','ae8751','d4b477','ead2a3'],
            swirl=math.tau, turbulence=2.5, tumble=0, fade_in=.01, fade_out=.1,
            time=0, travel=.01, linger=100, length=1.0, hold_path_end=True, stream_flow=.5)
events=[]
# Dense soft dust connects the sheet; sparse grains only describe its edges.
layers=[(36,10000,.6,1.0),(32,9000,.55,1.0),(25,6000,.5,.85),(36,4500,.75,0.0)]
for i,(width,count,size,dust) in enumerate(layers):
    angles=[-.06+(math.pi+.12)*k/11 for k in range(12)]
    if i%2: angles.reverse()
    path=[[640+math.cos(a)*260,520-math.sin(a)*260] for a in angles]
    events.append(dict(base,id=f'thomas_ring_{i}',path=path,width=width,count=count,
                       stream_curl=1, stream_edge=32, stream_flow=.5, turbulence=2,
                       size=size, sand_dust=dust,
                       ramp=(["33261c","705239","967249","c1a16c","dbc28d"] if i==0 else
                             ["40301e","9d7848","c5a163","dec08a","eed8ae"] if i==2 else base["ramp"])))

document = dict(name='蝎女 · 托马斯沙暴环', events=events,
                production=dict(radius=260,cell=[640,384],origin=[320,352],band_half=36))
style = dict(language='zh', renderer='quake', quake_style='pixel', quake_detail='fine', pixel=1, title=document['name'])
for name, data in [('combo',document), ('style',style)]:
    (FOLDER / (name+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(FOLDER/'prompt.md').write_text('连续翻涌的沙尘暴环：取消独立卷头，沿完整弧线连续折叠流动。多层薄尘互相交叠形成连贯沙带，外层稀疏细沙自然散开。视觉更宽，但仍留在原36px显示半宽内；圈间距260、扩张70、判定半宽16和时序全部不变。Studio swarm原生烘焙。\n',encoding='utf-8')
(FOLDER/'sandstorm_thomas_wave.tscn').write_text('[gd_scene format=3]\n\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/sandstorm_thomas_wave/combo.json"\nstyle_file = "res://combos/sandstorm_thomas_wave/style.json"\n',encoding='utf-8')
atlas = Image.open(GAME/'assets/bosses/sandstorm_fighter/body/thomas_knee_256x256_30f.png')
bottoms=[]
for i in range(30):
    x,y=(i%(atlas.width//256))*256,(i//(atlas.width//256))*256
    bottoms.append(atlas.crop((x,y,x+256,y+256)).getbbox()[3])
actions=json.loads((ROOT/'smear-combo-demo/characters/sandstorm_fighter/character.json').read_text(encoding='utf-8'))['actions']
data=dict(action=next(k for k in actions if '托马斯' in k), frame_bottoms=bottoms, intro_frames=list(range(6)),
          loop_frames=list(range(6,14)), recovery_frames=[14]+list(range(22,30)),
          frame_time=.083, spin_cycles=7, ring_radii=[140,400,660],
          field_start=.498, warning_time=1.35, active_time=2.85, fade_time=.45,
          ring_speed=70, ring_half_width=16, damage=12, source_frame_numbers='zero_based')
target=GAME/'assets/bosses/sandstorm_fighter/data/thomas_skill.json'
target.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Created editable sand-wave recipe and Thomas ground-frame contacts:', bottoms)

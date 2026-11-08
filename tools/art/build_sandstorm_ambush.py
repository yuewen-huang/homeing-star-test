"""Editable Studio sources for the veil and short, directional sand gust."""
import json, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
BASE = dict(t=0, do='swarm', material='sand', form='stream', at=[640,360],
            size=1.3, sand_grain=.5, sand_dust=1., sand_settle=0, sand_floor=1100,
            count=8500, look='mirror', ramp=['34291e','70583b','ab8953','c5a773','dbc292'],
            swirl=math.tau, turbulence=26, tumble=0, fade_in=.01, fade_out=.3,
            time=0, travel=.01, linger=100, length=1., hold_path_end=True,
            stream_flow=.5, stream_curl=1, stream_edge=150, width=150)
for name in ['veil','gust']:
    folder=ROOT/'combat-vfx-studio/combos'/('sandstorm_ambush_'+name)
    folder.mkdir(parents=True,exist_ok=True)
    if name=='veil':
        events=[]
        for i in range(8):
            y=-180+i*145
            path=[[-220+k*155,y+math.sin(k*.5+i)*60+k*6] for k in range(12)]
            if i%2: path.reverse()
            events.append(dict(BASE,id=f'veil_{i}',path=path))
    else:
        events=[dict(BASE,id='gust',path=[[550,365],[585,350],[630,355],[680,345],[720,345]],
                     width=35,stream_edge=45,count=3500,size=.7,turbulence=12,
                     fade_in=.03,fade_out=.3,linger=.55)]
    doc=dict(name='蝎女 · 沙幕' if name=='veil' else '蝎女 · 瞬移卷沙',events=events)
    style=dict(language='zh',renderer='quake',quake_style='pixel',quake_detail='fine',pixel=1)
    for filename,value in [('combo',doc),('style',style)]:
        (folder/(filename+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (folder/'prompt.md').write_text('全屏半透明沙尘暴的连续风流；叠加在角色前方仍须看清轮廓。局部瞬移使用短促卷沙，不画刀光。用 Studio swarm 原生烘焙。\n',encoding='utf-8')
    (folder/(folder.name+'.tscn')).write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/'+folder.name+'/combo.json"\nstyle_file = "res://combos/'+folder.name+'/style.json"\n',encoding='utf-8')
print('Created editable veil and gust presets')

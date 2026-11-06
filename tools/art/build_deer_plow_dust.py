"""Editable Combat VFX Studio quake recipes, shared verbatim by the game."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
profiles = {}
for key, height, density, width, seed in [('trail', 100, 1.8, 90, 61), ('lift', 155, 2.2, 130, 93), ('rain', 90, 1.0, 90, 107)]:
    event = dict(t=0, do='quake', x=640, y=520, unit='earth', form='surge', mode='radial',
                 width=width, perspective=.12, travel=.065, ease=.8, strength=.9,
                 body=False, unit_size=1.65 if key!='rain' else 1.0, spacing=30, cracks=False, wave=False, flash=0, shake=0,
                 debris='stone', debris_density=.16, debris_height=height,
                 dust=True, dust_height=height, dust_spread=width*.8, dust_density=density,
                 dust_time=.58, dust_color='c9b58c',
                 ramp=['211e19','463b2b','796444','b49a6a','ddc794'], seed=seed)
    title={'trail':'犁地扬尘','lift':'挑地扬土','rain':'落藤碎土'}[key]
    folder=ROOT/'combat-vfx-studio/combos'/f'deer_dust_{key}'
    folder.mkdir(parents=True,exist_ok=True)
    def write(path,data): path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    write(folder/'combo.json',dict(name='鹿·'+title,events=[event]))
    write(folder/'style.json',dict(language='zh',renderer='quake',quake_style='cel',quake_detail='balanced',pixel=2,title='鹿·'+title))
    if not (folder/(folder.name+'.tscn')).exists():
        subprocess.run([sys.executable,str(ROOT/'combat-vfx-studio/tools/new_combo.py'),folder.name,
                        '--project',str(ROOT/'combat-vfx-studio'),'--combo',str(folder/'combo.json'),
                        '--style',str(folder/'style.json'),'--force'],check=True)
    (folder/'prompt.md').write_text('复用地震分类土石、扬尘。犁地沿接地轨迹分段释放，土尘留在世界位置；上挑抛土更高。纯演出，伤害由原招式负责。\n',encoding='utf-8')
    profiles[key]=event|dict(x=0,y=-2)
write(ROOT/'homeing-star-game/assets/bosses/deer/fx/plow_dust.json',profiles)
print('Exported three Studio quake dust recipes')

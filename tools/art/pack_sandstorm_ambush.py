from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
target=ROOT/'homeing-star-game/assets/bosses/sandstorm_fighter/fx/ambush'
target.mkdir(parents=True,exist_ok=True)
for kind,cell,count,cols,rows in [('veil',(640,360),48,8,6),('gust',(256,256),24,6,4)]:
    atlas=Image.new('RGBA',(cell[0]*cols,cell[1]*rows))
    for i in range(count):
        frame=Image.open(ROOT/f'homeing-star-test/artifacts/sandstorm-ambush/{kind}/frame_{i:03d}.png')
        atlas.paste(frame,((i%cols)*cell[0],(i//cols)*cell[1]))
    atlas.save(target/f'{kind}_{cell[0]}x{cell[1]}_{count}f.png')
    for name in ['combo.json','style.json','prompt.md']:
        (target/(kind+'_'+name)).write_bytes((ROOT/f'combat-vfx-studio/combos/sandstorm_ambush_{kind}'/name).read_bytes())
(target/'SOURCE.md').write_text('Native Combat VFX Studio swarm render. Editable sources: combos/sandstorm_ambush_veil and sandstorm_ambush_gust. Veil 48 frames at 24fps; gust 24 at 40fps. Build/bake/pack tools live in homeing-star-test/tools/art. No runtime sibling dependency.\n',encoding='utf-8')
print('Packed native ambush effects')

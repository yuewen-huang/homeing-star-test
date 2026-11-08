from pathlib import Path
import json, shutil
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
target=ROOT/'homeing-star-game/assets/bosses/sandstorm_fighter/fx/signature'
target.mkdir(parents=True,exist_ok=True)
existing=json.loads((target/'manifest.json').read_text()) if (target/'manifest.json').exists() else {}
manifest={}
for folder in sorted((ROOT/'combat-vfx-studio/combos').glob('sandstorm_signature_*')):
    key=folder.name.removeprefix('sandstorm_signature_')
    if key=='scorpion' and existing.get(key,{}).get('kind')=='phase_locked_tail':
        manifest[key]=existing[key]
        continue  # The accepted rig is owned by import_sand_scorpion_finisher.py.
    spec=json.loads((folder/'combo.json').read_text(encoding='utf-8'))['bake']
    w,h=spec['cell']; count=spec['frames']; cols=4; rows=(count+cols-1)//cols
    atlas=Image.new('RGBA',(w*cols,h*rows))
    for i in range(count):
        image=Image.open(ROOT/f'homeing-star-test/artifacts/sandstorm-signature/bake/{key}/frame_{i:03d}.png')
        atlas.paste(image,(i%cols*w,i//cols*h))
    atlas.save(target/(key+'.png'))
    for name in ['combo.json','style.json','prompt.md']: shutil.copyfile(folder/name,target/(key+'_'+name))
    manifest[key]=dict(spec,columns=cols,rows=rows)
(target/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
if manifest.get('scorpion',{}).get('kind')!='phase_locked_tail':
    (target/'SOURCE.md').write_text('Editable sources: combat-vfx-studio/combos/sandstorm_signature_*. Native Studio swarm/quake render. Scorpion uses editable carapace/stinger formations at 60 FPS; other atlases at 30 FPS. Build/bake/pack scripts: homeing-star-test/tools/art/*sandstorm_signature*. All production atlases and recipes are local to the game. No runtime sibling dependency. sand_silhouette.gdshader only erodes the live animated ghost texture; Studio peel supplies its grains.\n',encoding='utf-8')
print('Packed signature atlases')

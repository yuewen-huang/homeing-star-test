"""Author editable Combat VFX Studio blade recipes; pack its native transparent bake."""
import json
import hashlib
import subprocess
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
STUDIO = ROOT / 'combat-vfx-studio'
GAME = ROOT / 'homeing-star-game'
SCRATCH = ROOT / 'homeing-star-test/artifacts/deer_horn_studio'
OUT = GAME / 'assets/bosses/deer/fx/horn_studio'
RECIPES = {
    'sweep': dict(radius=155, squash=.46, width=48, **{'from': 55, 'to': -65}, duration=.16, fade=.15, anchor=[95,-63]),
    'rush': dict(radius=210, squash=.19, width=62, **{'from': -55, 'to': 55}, duration=.075, fade=.19, anchor=[65,-46]),
    'plow': dict(radius=130, squash=.22, width=45, **{'from': -50, 'to': 55}, duration=.08, fade=.16, anchor=[78,-27]),
    'lift': dict(radius=132, squash=1.03, width=49, **{'from': 65, 'to': -105}, duration=.22, fade=.16, anchor=[72,-101]),
}
STYLE = dict(language='zh', pixel=2, thickness=1, blade_style='brush', palettes={
    'green':['fff8dc','d9e5a2','94a850','293d30']})

def author():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    for key, recipe in RECIPES.items():
        name = 'deer_horn_' + key
        event = dict(recipe, t=.25, do='slash', palette='green')
        anchor = event.pop('anchor')
        combo = dict(name=name, events=[event, dict(t=.25+min(recipe['duration']*.5,.055), do='hit', push=0, stop=0, shake=0)])
        (SCRATCH/'combo.json').write_text(json.dumps(combo,indent=2),encoding='utf-8')
        (SCRATCH/'style.json').write_text(json.dumps(dict(STYLE,title=name),indent=2),encoding='utf-8')
        subprocess.run([sys.executable,str(STUDIO/'tools/new_combo.py'),name,'--project',str(STUDIO),
            '--combo',str(SCRATCH/'combo.json'),'--style',str(SCRATCH/'style.json'),
            '--prompt','鹿角刀光：技能编辑器刀光横斩/突刺/上挑模板，手绘像素；保持原有战斗判定，只制作视觉。','--force'],check=True)
    (SCRATCH/'recipes.json').write_text(json.dumps(RECIPES,indent=2),encoding='utf-8')

def pack():
    OUT.mkdir(parents=True,exist_ok=True)
    manifest={}
    for key,recipe in RECIPES.items():
        frames=[Image.open(p).convert('RGBA') for p in sorted((SCRATCH/key).glob('frame_*.png'))]
        boxes=[im.getbbox() for im in frames if im.getbbox()]
        box=(min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes))
        w,h=box[2]-box[0],box[3]-box[1]
        atlas=Image.new('RGBA',(w*8,h*((len(frames)+7)//8)))
        for i,im in enumerate(frames): atlas.paste(im.crop(box),((i%8)*w,(i//8)*h))
        atlas.save(OUT/(key+'.png'))
        source=STUDIO/'combos'/('deer_horn_'+key)/'combo.json'
        manifest[key]=dict(file=key+'.png',size=[w,h],count=len(frames),fps=60,origin=[box[0]-256,box[1]-384],
            source=str(source.relative_to(STUDIO)),sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        review=Image.new('RGB',(w*4,h*2),(65,76,65))
        for slot,i in enumerate([1,3,6,9,12,15,18,min(len(frames)-1,23)]):
            tile=frames[min(i,len(frames)-1)].crop(box);review.paste(tile,((slot%4)*w,(slot//4)*h),tile)
        review.save(SCRATCH/(key+'_sheet.png'))
    (OUT/'profiles.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Packed four native Studio brush blade sheets')

if __name__=='__main__':
    pack() if '--pack' in sys.argv else author()

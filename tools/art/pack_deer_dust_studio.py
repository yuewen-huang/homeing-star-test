"""Trim and pack the native Studio bake; no substitute effect generation."""
import json
import hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'homeing-star-game/assets/bosses/deer/fx/dust_studio'
OUT.mkdir(parents=True,exist_ok=True)
manifest={}
for key in ['trail','lift','rain']:
    frames=[Image.open(f).convert('RGBA') for f in sorted((ROOT/'homeing-star-test/artifacts/deer_dust_studio'/key).glob('frame_*.png'))]
    assert len(frames)==42
    boxes=[im.getbbox() for im in frames if im.getbbox()]
    box=(min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes))
    assert box[0]>0 and box[1]>0 and box[2]<512 and box[3]<384, 'Bake is clipped'
    w,h=box[2]-box[0],box[3]-box[1]
    atlas=Image.new('RGBA',(w*8,h*6))
    for i,im in enumerate(frames): atlas.paste(im.crop(box),((i%8)*w,(i//8)*h))
    atlas.save(OUT/(key+'.png'))
    source=ROOT/'combat-vfx-studio/combos'/('deer_dust_'+key)/'combo.json'
    manifest[key]=dict(size=[w,h],count=len(frames),fps=60,origin=[box[0]-256,box[1]-280],source=str(source.relative_to(ROOT)),sha256=hashlib.sha256(source.read_bytes()).hexdigest())
(OUT/'profiles.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('Packed three native Studio quake dust sheets')

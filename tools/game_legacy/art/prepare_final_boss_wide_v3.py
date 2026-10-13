"""Prepare two-screen arena art without stretching existing tree silhouettes."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/sideview/environment/chapter_1_boss_rooms'
SIZE = (2560,720)
jobs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
manifest=[]
for job in jobs:
    name=job['name']
    raw=OUT/'source'/(name+'_raw.png')
    shutil.copy2(job['source'],raw)
    im=Image.open(raw).convert('RGBA')
    if 'ground' in name:
        alpha=im.getchannel('A')
        rear=next(y for y in range(im.height) if sum(v>=240 for v in alpha.crop((0,y,im.width,y+1)).getdata())>=im.width*.995)
        im=im.crop((0,rear,im.width,im.height))
        h=round(im.height*2560/im.width)
        im=im.resize((2560,h),Image.Resampling.LANCZOS)
        if h<205:
            raise ValueError('Insufficient platform depth')
        im=im.crop((0,0,2560,205))
    elif 'far' in name:
        im=ImageOps.fit(im,SIZE,Image.Resampling.LANCZOS)
    else:
        # Keep edge trees and ferns at their authored aspect ratio. Extend the
        # empty center when the generator supplies a narrower panorama.
        w=round(im.width*720/im.height)
        im=im.resize((w,720),Image.Resampling.LANCZOS)
        if w>2560:
            im=ImageOps.fit(im,SIZE,Image.Resampling.LANCZOS)
        else:
            canvas=Image.new('RGBA',SIZE)
            half=w//2
            canvas.alpha_composite(im.crop((0,0,half,720)),(0,0))
            canvas.alpha_composite(im.crop((half,0,w,720)),(2560-(w-half),0))
            im=canvas
    im.save(OUT/(name+'.png'))
    manifest.append({**job,'source':'source/'+raw.name,'file':name+'.png','size':list(im.size)})
(OUT/'manifest_final_wide_v3.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
im=Image.open(OUT/'final_far_wide_v3.png').convert('RGBA')
im.alpha_composite(Image.open(OUT/'final_mid_wide_v3.png').convert('RGBA'))
im.alpha_composite(Image.open(OUT/'final_ground_wide_v3.png').convert('RGBA'),(0,515))
im.alpha_composite(Image.open(OUT/'final_fore_wide_v3.png').convert('RGBA'))
im.convert('RGB').save(OUT/'previews/final_wide_composition_v3.jpg',quality=92)
print('Prepared final arena layers: 2560x720; platform: 2560x205')

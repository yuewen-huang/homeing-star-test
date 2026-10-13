"""Build the wide floor from two native-resolution panels without upscaling."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/sideview/environment/chapter_1_boss_rooms'
jobs=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
panels=[]
manifest=[]
for job in jobs:
    name=job['name']
    raw=OUT/'source'/(name+'_raw.png')
    shutil.copy2(job['source'],raw)
    im=Image.open(raw).convert('RGBA')
    native_size=list(im.size)
    if im.width<1312:
        raise ValueError('Ground panels must never be enlarged')
    alpha=im.getchannel('A')
    rear=next(y for y in range(im.height) if sum(v>=240 for v in alpha.crop((0,y,im.width,y+1)).getdata())>=im.width*.995)
    im=im.crop((0,rear,im.width,im.height))
    scaled_h=round(im.height*1312/im.width)
    if scaled_h<205:
        raise ValueError('Not enough native terrain depth')
    im=im.resize((1312,scaled_h),Image.Resampling.LANCZOS).crop((0,0,1312,205))
    im.save(OUT/(name+'.png'))
    panels.append(im)
    manifest.append({**job,'source':'source/'+raw.name,'file':name+'.png',
                     'native_size':native_size,'runtime_size':[1312,205],
                     'scale':1312/native_size[0],'source_rear_row':rear})
left,right=panels
combined=Image.new('RGBA',(2560,205))
combined.paste(left,(0,0))
combined.paste(right.crop((64,0,1312,205)),(1312,0))
# A narrow 64px overlap smooths only the join between independently painted
# panels; the remainder is kept at its native downsampled detail resolution.
mask=Image.new('L',(64,205))
mask.putdata([round(x*255/63) for y in range(205) for x in range(64)])
join=Image.composite(right.crop((0,0,64,205)),left.crop((1248,0,1312,205)),mask)
combined.paste(join,(1248,0))
combined.save(OUT/'final_ground_wide_v4.png')
(OUT/'manifest_final_ground_v4.json').write_text(json.dumps({'method':'two downsampled panels, 64px join; no upscaling','file':'final_ground_wide_v4.png','size':[2560,205],'panels':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
print('Ground V4 prepared without upscaling:',[(r['native_size'],r['scale']) for r in manifest])

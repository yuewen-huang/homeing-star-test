"""Preserve shallow-perspective platform tops and place feet inside the plane."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/sideview/environment/chapter_1_boss_rooms'
TOP = 515

jobs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
manifest = []
for job in jobs:
    name = job['name']
    raw = OUT / 'source' / (name+'_raw_v2.png')
    shutil.copy2(job['source'],raw)
    im = Image.open(raw).convert('RGBA')
    alpha = im.getchannel('A')
    rear = next(y for y in range(im.height)
                if sum(v >= 240 for v in alpha.crop((0,y,im.width,y+1)).getdata()) >= im.width*.995)
    im = im.crop((0,rear,im.width,im.height))
    scaled_h = round(im.height * 1280/im.width)
    im = im.resize((1280,scaled_h),Image.Resampling.LANCZOS)
    if scaled_h < 205:
        raise ValueError(f'{name}: platform too short: {scaled_h}')
    im = im.crop((0,0,1280,205))
    im.save(OUT/(name+'_v2.png'))
    manifest.append({**job,'source':'source/'+raw.name,'file':name+'_v2.png',
                     'size':[1280,205],'visual_top_y':TOP,'standing_y':555,
                     'source_rear_rim_row':rear})
    print(name, 'source rear',rear,'scaled height',scaled_h)
(OUT/'manifest_ground_v2.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

far={'wind':'chapter_1_wind/wind_canopy_far.png','vine':'chapter_1_vine/vine_forest_far.png',
     'mist':'chapter_1_mist/mist_forest_far_01.png','root':'chapter_1_root/layers/01_far_cavern.png'}
cores={'wind':'upper_left','vine':'upper_right','mist':'lower_left','root':'lower_right'}
board=Image.new('RGB',(1280,1170),(22,30,32))
for i,region in enumerate(['wind','vine','mist','root','final']):
    bg=OUT/'final_far_v1.png' if region=='final' else OUT.parent/far[region]
    im=ImageOps.fit(Image.open(bg).convert('RGBA'),(1280,720),Image.Resampling.LANCZOS)
    if region=='final':
        im.alpha_composite(Image.open(OUT/'final_mid_v1.png').convert('RGBA'))
    im.alpha_composite(Image.open(OUT/(region+'_ground_v2.png')).convert('RGBA'),(0,TOP))
    if region in cores:
        core=Image.open(ROOT/'assets/sideview/bosses/amethyst_tree_core'/(cores[region]+'.png')).convert('RGBA')
        core=core.resize((555,555),Image.Resampling.LANCZOS)
        im.alpha_composite(core,(725 if region in ['wind','mist'] else 0,0))
    else:
        im.alpha_composite(Image.open(OUT/'final_fore_v1.png').convert('RGBA'))
    im.convert('RGB').save(OUT/'previews'/(region+'_composition_v2.jpg'),quality=92)
    x,y=(i%2)*640,(i//2)*390
    board.paste(im.convert('RGB').resize((640,360),Image.Resampling.LANCZOS),(x,y+30))
    ImageDraw.Draw(board).text((x+12,y+8),region.upper()+' V2',fill=(230,240,220))
board.save(OUT/'previews/arena_contact_sheet_v2.jpg',quality=92)

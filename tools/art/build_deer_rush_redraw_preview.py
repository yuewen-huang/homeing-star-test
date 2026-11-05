"""Standalone art comparison. Never writes game assets or combat code."""
from pathlib import Path
import argparse, json, io, zipfile, math
from PIL import Image, ImageDraw, ImageFont

ap=argparse.ArgumentParser()
ap.add_argument('--assets',required=True)
a=ap.parse_args(); root=Path(a.assets)
meta=json.loads((root/'source_timing.json').read_text())
CELL=160

def foot_anchor(im):
    alpha=im.getchannel('A'); box=alpha.point(lambda x:255 if x>=128 else 0).getbbox()
    if box is None: raise ValueError('Empty frame')
    band=alpha.crop((0,max(0,box[3]-5),im.width,box[3])).point(lambda x:255 if x>=128 else 0).getbbox()
    return ((band[0]+band[2])/2,box[3])

old_sheet=Image.open(root/'old_pose_grid.png').convert('RGBA')
old=[]
for i in range(28):
    old.append(old_sheet.crop((i%7*256,i//7*256,(i%7+1)*256,(i//7+1)*256)).resize((CELL,CELL),Image.Resampling.NEAREST))

new=[]; shifts=[]
for name,cols,rows,used in [('prep',3,2,6),('rush',4,3,11),('recover',4,3,11)]:
    sheet=Image.open(root/(name+'_raw.png')).convert('RGBA')
    for j in range(used):
        bounds=(round(j%cols*sheet.width/cols),round(j//cols*sheet.height/rows),round((j%cols+1)*sheet.width/cols),round((j//cols+1)*sheet.height/rows))
        f=sheet.crop(bounds)
        # Same proportional scale for ALL poses. Never fit each frame to its bounds.
        size=round(CELL*.78)
        f=f.resize((size,size),Image.Resampling.NEAREST)
        f.putalpha(f.getchannel('A').point(lambda x:255 if x>=128 else 0))
        x,y=foot_anchor(f); tx,ty=foot_anchor(old[len(new)])
        dx,dy=round(tx-x),round(ty-y)
        normalized=Image.new('RGBA',(CELL,CELL));normalized.alpha_composite(f,(dx,dy))
        if normalized.getchannel('A').getbbox() is None: raise ValueError('Empty normalized sprite')
        new.append(normalized);shifts.append({'segment':name,'frame':j,'offset':[dx,dy]})

# One shared finite palette for every new frame, plus alpha.
palette_source=Image.new('RGB',(CELL*7,CELL*4),(38,43,49))
for i,f in enumerate(new): palette_source.paste(f,(i%7*CELL,i//7*CELL),f)
palette=palette_source.quantize(colors=32,method=Image.Quantize.MEDIANCUT)
for i,f in enumerate(new):
    alpha=f.getchannel('A'); f=f.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA');f.putalpha(alpha);new[i]=f

for name,frames in [('old_normalized',old),('new_normalized',new)]:
    atlas=Image.new('RGBA',(CELL*7,CELL*4))
    for i,f in enumerate(frames): atlas.alpha_composite(f,(i%7*CELL,i//7*CELL))
    atlas.save(root/(name+'.png'))

total=sum(s['duration'] for s in meta['slots'])
def frame_at(t):
    for i,s in enumerate(meta['slots']):
        if t<s['duration']: return i
        t-=s['duration']
    return 27

def world_x(t):
    d=meta['rush_duration'];t=max(0,min(d,t-.68));area=d-.05
    moved=t-.02
    if t<.04:moved=t*t/.08
    elif t>d-.06:moved=area-(d-t)**2/.12
    return 660*max(0,min(1,moved/area))

font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',19)
def render(t):
    im=Image.new('RGB',(960,540),(29,34,42));draw=ImageDraw.Draw(im)
    idx=frame_at(t);phase='WIND-UP' if t<.68 else ('RUSH' if t<.68+meta['rush_duration'] else 'RECOVERY / OPENING')
    draw.text((22,12),'DEER RUSH - original timing / identical travel',font=font,fill='#e1e7e5')
    draw.text((610,12),phase,font=font,fill='#bfd983')
    x=150+world_x(t)*.8
    for row,(frames,label) in enumerate([(old,'ORIGINAL'),(new,'REDRAW')]):
        floor=245+row*260
        draw.line((15,floor,945,floor),fill='#6b757c',width=2)
        for gx in range(30,960,80):draw.line((gx,52+row*260,gx,floor),fill='#353e47')
        draw.text((22,45+row*260),label,font=font,fill='#b9c5c7')
        f=frames[idx].resize((240,240),Image.Resampling.NEAREST)
        im.paste(f,(round(x-60*1.5),round(floor-145*1.5)),f)
        draw.line((round(x),floor+4,round(x),floor+11),fill='#c8dd8d',width=2)
    return im

times=[min(total,max(0,i*.04-.4)) for i in range(math.ceil((total+.95)/.04))]
renders=[render(t) for t in times]
pal=Image.new('RGB',(240,135*len(renders)))
for i,f in enumerate(renders):pal.paste(f.resize((240,135)),(0,135*i))
pal=pal.quantize(colors=192,method=Image.Quantize.MEDIANCUT)
seq=[f.quantize(palette=pal,dither=Image.Dither.NONE) for f in renders]
seq[0].save(root/'rush_comparison.gif',save_all=True,append_images=seq[1:],duration=40,loop=0,disposal=1,optimize=True)
for name,t in [('prep',.55),('rush',.98),('recover',1.60),('idle',2.20)]:render(t).save(root/('check_'+name+'.png'))

with zipfile.ZipFile(root/'redrawn_frames.zip','w',zipfile.ZIP_DEFLATED) as z:
    for i,f in enumerate(new):
        b=io.BytesIO();f.save(b,format='PNG');z.writestr(f'{i:02d}_{meta["slots"][i]["clip"]}.png',b.getvalue())
    z.writestr('timing.json',json.dumps(meta,indent=2))

report={'frames':len(new),'action_seconds':total,'prep_seconds':.68,'rush_seconds':meta['rush_duration'],'opening_seconds':1.0,'rush_distance_world_px':660,'logical_cell':CELL,'shared_scale':.78,'palette_colors':32,'alpha':'binary threshold 128','anchor':'per-frame hoof support aligned to corresponding original; no independent frame scaling','shifts':shifts,'status':'art experiment only; generated poses approximate source; not production-approved; game unchanged'}
(root/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='shifts'}))

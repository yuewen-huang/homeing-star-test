"""Deterministic pixel transfer trial; user-authorized palette/feature edits."""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import csv
import argparse

parser=argparse.ArgumentParser()
parser.add_argument('--full',action='store_true')
args=parser.parse_args()
COUNT=10 if args.full else 3

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ('assets/sideview/characters/lan/idle-cat-v1' if args.full else 'assets/sideview/characters/lan/ear-tail-trial')
OUT.mkdir(exist_ok=True)
SOURCE = ROOT / 'assets/sideview/characters/lan/idle.png'
USER = ROOT / 'PendingArt/character/主角-岚/模板/frame01-recolored.png'
BASE = ROOT / 'assets/sideview/characters/lan/palette-trial/frame01-recolored.png'

def load(path):
    return Image.open(path).convert('RGBA')

def preview(images, labels, path):
    canvas = Image.new('RGB', (len(images)*480, 595), '#333338')
    draw = ImageDraw.Draw(canvas)
    for i, (im, label) in enumerate(zip(images, labels)):
        draw.text((i*480+10, 8), label, fill='white')
        back = Image.new('RGBA', (46,55))
        for y in range(55):
            for x in range(46):
                v=100 if (x//4+y//4)%2 else 115
                back.putpixel((x,y),(v,v,v,255))
        back.alpha_composite(im)
        canvas.paste(back.convert('RGB').resize((460,550),Image.Resampling.NEAREST),(i*480+10,30))
    canvas.save(path)

sheet=load(SOURCE)
assert sheet.size==(460,55)
frames=[sheet.crop((46*i,0,46*(i+1),55)) for i in range(COUNT)]
user=load(USER)
base=load(BASE)
assert user.size==base.size==(46,55)
diff=[]
mask=Image.new('RGBA',(46,55))
for y in range(55):
    for x in range(46):
        a,b=base.getpixel((x,y)),user.getpixel((x,y))
        if a!=b and (a[3] or b[3]):
            diff.append((x,y,a,b))
            mask.putpixel((x,y),(255,80,100,255) if not b[3] else (80,255,130,255))
preview([base,user,mask],['BASE','USER EDIT','CHANGES green=paint red=erase'],OUT/'diagnostic-edits.png')
preview(frames[:3],['SOURCE 1','SOURCE 2','SOURCE 3'],OUT/'diagnostic-source.png')
print('Edited pixel count:',len(diff))

def shift_fit(box, limit=3):
    """Read-only regional exact-color alignment against the template."""
    x0,y0,x1,y1=box
    result=[]
    for target in frames:
        candidates=[]
        for dy in range(-limit,limit+1):
            for dx in range(-limit,limit+1):
                same=total=0
                for y in range(y0,y1):
                    for x in range(x0,x1):
                        a=frames[0].getpixel((x,y))
                        if not a[3]: continue
                        total+=1
                        xx,yy=x+dx,y+dy
                        if 0<=xx<46 and 0<=yy<55 and target.getpixel((xx,yy))==a: same+=1
                candidates.append((same/total,-abs(dx)-abs(dy),dx,dy,same,total))
        best=max(candidates)
        result.append({'dx':best[2],'dy':best[3],'match':best[4],'pixels':best[5]})
    return result

heads=shift_fit((0,0,28,11))
bodies=shift_fit((16,29,29,41))
print('Head alignment:',heads)
print('Torso alignment:',bodies)

# Reuse the audited color table, keeping its regional alternatives.
with (ROOT/'assets/sideview/characters/lan/palette-trial/frame01-pixel-map.csv').open(encoding='utf-8-sig') as f:
    rows=list(csv.DictReader(f))
palette={}
for row in rows:
    rgb=tuple(bytes.fromhex(row['source'][1:]))
    palette.setdefault(rgb,[]).append((int(row['x']),int(row['y']),tuple(bytes.fromhex(row['target'][1:]))))

ear_edits=[d for d in diff if d[1]<11]
tail_edits=[d for d in diff if d[0]>=35 and 20<=d[1]<=32]
other_edits=[d for d in diff if d not in ear_edits and d not in tail_edits]
results=[user.copy()]
audit=[]
layers=[]
for i in range(1,COUNT):
    source=frames[i]
    recolor=Image.new('RGBA',(46,55))
    for y in range(55):
        for x in range(46):
            p=source.getpixel((x,y))
            if not p[3]:continue
            if p[:3] not in palette: raise ValueError(f'Unmapped color {p}')
            anchor=heads[i] if y<22 else bodies[i]
            xx,yy=x-anchor['dx'],y-anchor['dy']
            # Nearest same-source-color sample resolves material overlap deterministically.
            _,_,rgb=min(palette[p[:3]],key=lambda v:(v[0]-xx)**2+(v[1]-yy)**2)
            recolor.putpixel((x,y),rgb+(p[3],))
    assert recolor.getchannel('A').tobytes()==source.getchannel('A').tobytes()
    character=recolor.copy()
    touched=set()
    # Later torso poses shift the old trim independently of the body anchor.
    # Remove only those old brown trim pixels before placing the user's seam.
    # The three already approved frames remain byte-for-byte untouched.
    if i>=3:
        for y in range(29+bodies[i]['dy'],40+bodies[i]['dy']):
            for x in range(17,29):
                if source.getpixel((x,y))[:3] in ((166,75,10),(140,35,9)):
                    character.putpixel((x,y),(39,72,76,255))
                    touched.add((x,y))
    for x,y,old,new in ear_edits+other_edits:
        anchor=heads[i] if y<22 else bodies[i]
        xx,yy=x+anchor['dx'],y+anchor['dy']
        assert 0<=xx<46 and 0<=yy<55
        if y>=22 and not source.getpixel((xx,yy))[3]:
            raise ValueError('Clothing edit left body silhouette')
        character.putpixel((xx,yy),new)
        touched.add((xx,yy))
    tail=Image.new('RGBA',(46,55))
    for x,y,old,new in tail_edits:
        xx,yy=x+bodies[i]['dx'],y+bodies[i]['dy']
        assert 0<=xx<46 and 0<=yy<55
        tail.putpixel((xx,yy),new)
    result=tail.copy()
    result.alpha_composite(character)
    # Verify all non-edit opaque pixels are exactly the recolored template,
    # including the moving weapon, limbs and boots. Tail is always behind.
    preserved=0
    for y in range(55):
        for x in range(46):
            if source.getpixel((x,y))[3] and (x,y) not in touched:
                assert result.getpixel((x,y))==recolor.getpixel((x,y))
                preserved+=1
    results.append(result)
    layers.append((character,tail))
    recolor.save(OUT/f'frame{i+1:02}-palette-base.png')
    character.save(OUT/f'frame{i+1:02}-character.png')
    tail.save(OUT/f'frame{i+1:02}-tail-layer.png')
    audit.append({'frame':i+1,'head':heads[i],'torso':bodies[i], 'unchanged_opaque_pixels_outside_edits':preserved,'edit_pixels':len(touched),'palette_alpha_exact':True})
for i,im in enumerate(results):
    im.save(OUT/f'frame{i+1:02}-cat.png')
assert results[0].tobytes()==user.tobytes()
strip=Image.new('RGBA',(46*COUNT,55))
for i,im in enumerate(results):strip.paste(im,(i*46,0))
strip.save(OUT/('idle-cat-10frames.png' if args.full else 'idle-first3-46x55.png'))
if args.full:
    preview(results[:5],[str(i+1) for i in range(5)],OUT/'frames01-05-10x.png')
    preview(results[5:],[str(i+6) for i in range(5)],OUT/'frames06-10-10x.png')
else:
    preview(results,['1 USER','2 AUTO','3 AUTO'],OUT/'first3-comparison-10x.png')
# Ping-pong is a review aid, not a claim to be the complete ten-frame loop.
gif=[]
for idx in (range(COUNT) if args.full else (0,1,2,1)):
    backdrop=Image.new('RGBA',(46,55),(90,90,95,255))
    backdrop.alpha_composite(results[idx])
    gif.append(backdrop.convert('RGB').resize((368,440),Image.Resampling.NEAREST))
gif[0].save(OUT/('idle-preview.gif' if args.full else 'first3-pingpong-preview.gif'),save_all=True,append_images=gif[1:],duration=([120,130]*5 if args.full else 250),loop=0,disposal=2)
if args.full:
    for i in range(3):
        approved=load(ROOT/f'assets/sideview/characters/lan/ear-tail-trial/frame{i+1:02}-cat.png')
        assert results[i].tobytes()==approved.tobytes(),f'Approved frame {i+1} changed'
(OUT/'validation.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
print(json.dumps(audit,indent=2))

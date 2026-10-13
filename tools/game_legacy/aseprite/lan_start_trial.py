"""Two-frame start-walk draft; deterministic reference-pixel transfer."""
from pathlib import Path
from PIL import Image, ImageDraw
import csv,json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/sideview/characters/lan/start-cat-draft-v1'
OUT.mkdir(exist_ok=True)
def load(p): return Image.open(ROOT/p).convert('RGBA')
idle=load('assets/sideview/characters/lan/palette-trial/frame01-original.png')
base=load('assets/sideview/characters/lan/palette-trial/frame01-recolored.png')
approved=load('assets/sideview/characters/lan/idle.png').crop((0,0,46,55))
sheet=load('assets/sideview/characters/lan/from_idle.png')
assert sheet.size==(90,58)
frames=[sheet.crop((i*45,0,(i+1)*45,58)) for i in range(2)]
def preview(images,labels,name):
    out=Image.new('RGB',(len(images)*470,620),'#343438'); d=ImageDraw.Draw(out)
    for i,(im,label) in enumerate(zip(images,labels)):
        bg=Image.new('RGBA',im.size)
        for y in range(im.height):
            for x in range(im.width):
                v=100+15*((x//4+y//4)%2);bg.putpixel((x,y),(v,v,v,255))
        bg.alpha_composite(im)
        out.paste(bg.convert('RGB').resize((im.width*10,im.height*10),Image.Resampling.NEAREST),(i*470+10,30))
        d.text((i*470+10,8),label,fill='white')
    out.save(OUT/name)
preview(frames,['SOURCE 1','SOURCE 2'],'source-10x.png')
def fit(target,box):
    scores=[]
    for dy in range(-5,6):
        for dx in range(-5,6):
            n=total=0
            for y in range(box[1],box[3]):
                for x in range(box[0],box[2]):
                    p=idle.getpixel((x,y))
                    if not p[3]:continue
                    total+=1
                    xx,yy=x+dx,y+dy
                    if 0<=xx<45 and 0<=yy<58 and target.getpixel((xx,yy))==p:n+=1
            scores.append((n,-abs(dx)-abs(dy),dx,dy,total))
    n,_,dx,dy,total=max(scores)
    return dx,dy,n,total
pal={}
with (ROOT/'assets/sideview/characters/lan/palette-trial/frame01-pixel-map.csv').open(encoding='utf-8-sig') as f:
    for r in csv.DictReader(f):
        pal.setdefault(tuple(bytes.fromhex(r['source'][1:])),[]).append((int(r['x']),int(r['y']),tuple(bytes.fromhex(r['target'][1:]))))
# Additional dark-violet shade occurs only in the start sheet.
pal[(50,29,112)]=[(0,0,(39,72,76))]
edits=[]
for y in range(55):
    for x in range(46):
        a,b=base.getpixel((x,y)),approved.getpixel((x,y))
        if a!=b and (a[3] or b[3]):edits.append((x,y,b))
results=[];audit=[]
for i,src in enumerate(frames):
    head=fit(src,(0,0,28,11));body=fit(src,(16,29,29,41))
    print('FRAME',i+1,'HEAD',head,'BODY',body)
    recolor=Image.new('RGBA',(45,58))
    for y in range(58):
        for x in range(45):
            p=src.getpixel((x,y))
            if not p[3]:continue
            anchor=head if y<22+head[1] else body
            xx,yy=x-anchor[0],y-anchor[1]
            _,_,rgb=min(pal[p[:3]],key=lambda a:(a[0]-xx)**2+(a[1]-yy)**2)
            recolor.putpixel((x,y),rgb+(p[3],))
    assert recolor.getchannel('A').tobytes()==src.getchannel('A').tobytes()
    char=recolor.copy();tail=Image.new('RGBA',src.size);touched=set();skipped=[]
    # Horn placement is slightly different from idle; clear the complete source
    # horn mask before applying the user's ear pixels.
    horn_colors={(169,110,103),(77,47,30),(81,55,63)}
    for y in range(0,12):
        for x in range(0,29):
            if src.getpixel((x,y))[3] and src.getpixel((x,y))[:3] in horn_colors:
                replacement=(0,0,0,0) if x<10 else ((254,230,165,255) if x<21 else (248,208,131,255))
                char.putpixel((x,y),replacement);touched.add((x,y))
    for y in range(29+body[1],41+body[1]):
        for x in range(15,30):
            if src.getpixel((x,y))[3] and src.getpixel((x,y))[:3] in ((166,75,10),(140,35,9)):
                char.putpixel((x,y),(39,72,76,255));touched.add((x,y))
    for x,y,p in edits:
        istail=x>=35 and 20<=y<=32
        anchor=head if y<22 else body
        xx,yy=x+anchor[0],y+anchor[1]
        if not(0<=xx<45 and 0<=yy<58):skipped.append([x,y]);continue
        if istail:tail.putpixel((xx,yy),p)
        elif y<11 or (src.getpixel((xx,yy))[3] and x<30):
            char.putpixel((xx,yy),p);touched.add((xx,yy))
    result=tail.copy();result.alpha_composite(char)
    for y in range(58):
        for x in range(45):
            if src.getpixel((x,y))[3] and (x,y) not in touched:
                assert result.getpixel((x,y))==recolor.getpixel((x,y))
    results.append(result)
    result.save(OUT/f'start-frame{i+1:02}.png')
    char.save(OUT/f'start-frame{i+1:02}-character.png');tail.save(OUT/f'start-frame{i+1:02}-tail.png')
    audit.append(dict(frame=i+1,head=head,body=body,skipped=skipped,palette_alpha_exact=True))
strip=Image.new('RGBA',(90,58))
for i,im in enumerate(results):strip.paste(im,(45*i,0))
strip.save(OUT/'start-cat-2frames.png')
preview(results,['DRAFT 1','DRAFT 2'],'draft-10x.png')
preview([approved]+results,['APPROVED IDLE','START 1','START 2'],'idle-to-start-10x.png')
(OUT/'validation.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')

"""Pixel-preserving walk recolor with pose-fitted ears and rear-layer tail."""
from pathlib import Path
from PIL import Image, ImageDraw
import csv,json,math
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/sideview/characters/lan/walk-cat-draft-v1'
OUT.mkdir(exist_ok=True)
def load(p):return Image.open(ROOT/p).convert('RGBA')
source=load('assets/sideview/characters/lan/walk.png')
assert source.size==(180,348)
frames=[source.crop(((i%4)*45,(i//4)*58,(i%4+1)*45,(i//4+1)*58)) for i in range(24)]
def contact(images,labels,name,columns=4,scale=6):
    w,h=45*scale+16,58*scale+28
    out=Image.new('RGB',(w*columns,h*math.ceil(len(images)/columns)),'#343438');d=ImageDraw.Draw(out)
    for i,(im,label) in enumerate(zip(images,labels)):
        bg=Image.new('RGBA',im.size)
        for y in range(im.height):
            for x in range(im.width):
                v=100+15*((x//4+y//4)%2);bg.putpixel((x,y),(v,v,v,255))
        bg.alpha_composite(im)
        ox,oy=(i%columns)*w+8,(i//columns)*h
        out.paste(bg.convert('RGB').resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST),(ox,oy+22))
        d.text((ox,oy+5),label,fill='white')
    out.save(OUT/name)
contact(frames[:8],[str(i+1) for i in range(8)],'source01-08.png')
contact(frames[8:16],[str(i+9) for i in range(8)],'source09-16.png')
contact(frames[16:],[str(i+17) for i in range(8)],'source17-24.png')

with (ROOT/'assets/sideview/characters/lan/palette-trial/frame01-pixel-map.csv').open(encoding='utf-8-sig') as f:
    rows=list(csv.DictReader(f))
materials={r['material']:tuple(bytes.fromhex(r['target'][1:]))+(255,) for r in rows}
color_map={tuple(bytes.fromhex(r['source'][1:])):r['material'] for r in rows}
color_map.update({(50,29,112):'clothShade',(145,88,76):'leather',
                  (43,122,76):'eye',(39,113,72):'eyeDark',(251,249,245):'glint'})
cloth_colors={(28,21,77),(3,33,188),(21,16,55),(64,34,95),(47,24,80),(50,29,112)}
horn_colors={(169,110,103),(77,47,30),(81,55,63),(145,88,76)}
results=[];audit=[]
# Narrow side-view ears. Coordinates and color clusters are intentionally small
# enough for the template head, rather than resampling the much larger concept.
near=['s.....','ss....','sfs...','sffs..','sfffs.','sffhs.','.shhs.','..hh..']
far=['ss...','sfs..','.sfs.','..ss.']
ear_colors={'s':materials['furShade'],'f':(224,192,156,255),'h':materials['hair']}
for i,src in enumerate(frames):
    eye_points=[(x,y) for y in range(25) for x in range(45) if src.getpixel((x,y))[:3] in ((43,122,76),(39,113,72)) and src.getpixel((x,y))[3]]
    eye_y=min(y for x,y in eye_points); bob=eye_y-13
    recolor=Image.new('RGBA',(45,58))
    for y in range(58):
        for x in range(45):
            p=src.getpixel((x,y))
            if not p[3]:continue
            rgb=p[:3]; material=color_map[rgb]
            # Same purple is hair/neck shadow above, skin/hands below.
            if rgb==(173,95,173):material='hairDark' if y<=eye_y+12 else 'furShade'
            if rgb==(173,95,173) and x>=17 and y<=eye_y+8:material='hairShade'
            if rgb==(136,35,35):material='furDark' if y<=eye_y+11 else 'leather'
            if rgb==(140,35,9):material='creamShade' if eye_y+9<=y<=eye_y+27 else 'furDark'
            if rgb==(255,140,94):material='fur'
            if rgb==(224,94,43):material='furShade'
            recolor.putpixel((x,y),materials[material])
    assert recolor.getchannel('A').tobytes()==src.getchannel('A').tobytes()
    character=recolor.copy();touched=set()
    # Remove original horns exactly by their material mask in the crown region.
    for y in range(0,11+bob):
        for x in range(27):
            p=src.getpixel((x,y))
            if p[3] and p[:3] in horn_colors:
                # Above the white crown or beyond its front edge was exterior horn.
                q=(0,0,0,0) if x<7 or y<2+bob else materials['hairLight']
                character.putpixel((x,y),q);touched.add((x,y))
    ears=Image.new('RGBA',(45,58))
    for pattern,ox,oy in ((far,5,4+bob),(near,15,bob)):
        for yy,row in enumerate(pattern):
            for xx,symbol in enumerate(row):
                if symbol!='.':
                    p=(ox+xx,oy+yy);ears.putpixel(p,ear_colors[symbol]);character.putpixel(p,ear_colors[symbol]);touched.add(p)
    # Profile feline nose occupies one existing face-edge pixel, following the eye.
    candidates=[(x,y) for y in range(eye_y+2,eye_y+5) for x in range(5,12) if src.getpixel((x,y))==(255,140,94,255)]
    if candidates:
        nose=min(candidates,key=lambda p:(p[0],abs(p[1]-(eye_y+3))))
        character.putpixel(nose,materials['furDark']);touched.add(nose)
    # Find the central garment hem, excluding the sword and outstretched sleeves.
    torso=[(x,y) for y in range(eye_y+15,49) for x in range(12,25) if src.getpixel((x,y))[:3] in cloth_colors and src.getpixel((x,y))[3]]
    hem=max(y for x,y in torso)
    root_y=hem-4
    root_candidates=[x for yy in range(root_y-1,root_y+2) for x in range(16,31) if src.getpixel((x,yy))[:3] in cloth_colors and src.getpixel((x,yy))[3]]
    # Central pelvis anchor follows the measured head/body bob. The rear sleeve
    # and sword sweep across the hem mask, so its rightmost pixel is NOT a hip.
    root_x=24
    root_y=38+bob
    # A 24-frame closed periodic curve gives small secondary motion, behind
    # all original foreground pixels. No limb or weapon pixels are repainted.
    sway=round(math.sin(2*math.pi*i/24))
    lift=round(math.cos(2*math.pi*i/24))
    points=[(root_x-3,root_y),(min(root_x+7,37),root_y+2),(42+sway,root_y-7),(38+sway,root_y-13+lift)]
    curve=[]
    for j in range(41):
        t=j/40;u=1-t
        x=round(u**3*points[0][0]+3*u*u*t*points[1][0]+3*u*t*t*points[2][0]+t**3*points[3][0])
        y=round(u**3*points[0][1]+3*u*u*t*points[1][1]+3*u*t*t*points[2][1]+t**3*points[3][1])
        if not curve or curve[-1]!=(x,y):curve.append((x,y))
    tail=Image.new('RGBA',(45,58));td=ImageDraw.Draw(tail)
    td.line(curve,fill=materials['hairDark'],width=4)
    td.line(curve,fill=materials['hair'],width=2)
    td.line(curve[-3:],fill=materials['hairLight'],width=2)
    result=tail.copy();result.alpha_composite(character)
    for y in range(58):
        for x in range(45):
            if src.getpixel((x,y))[3] and (x,y) not in touched:
                assert result.getpixel((x,y))==recolor.getpixel((x,y))
    results.append(result)
    result.save(OUT/f'walk-frame{i+1:02}.png')
    character.save(OUT/f'walk-frame{i+1:02}-character.png')
    tail.save(OUT/f'walk-frame{i+1:02}-tail.png')
    ears.save(OUT/f'walk-frame{i+1:02}-ears.png')
    audit.append(dict(frame=i+1,head_bob=bob,tail_root=[root_x,root_y],tail_tip=list(curve[-1]),palette_alpha_exact=True,foreground_preserved_outside_head_edits=True))
out=Image.new('RGBA',(180,348))
for i,im in enumerate(results):out.paste(im,((i%4)*45,(i//4)*58))
out.save(OUT/'walk-cat-24frames.png')
for start in (0,8,16):contact(results[start:start+8],[str(i+1) for i in range(start,start+8)],f'draft{start+1:02}-{start+8:02}-6x.png')
gif=[]
for im in results:
    bg=Image.new('RGBA',(45,58),(90,90,95,255));bg.alpha_composite(im)
    gif.append(bg.convert('RGB').resize((270,348),Image.Resampling.NEAREST))
gif[0].save(OUT/'walk-preview.gif',save_all=True,append_images=gif[1:],duration=[60,60,60,70]*6,loop=0,disposal=2)
gif[0].save(OUT/'walk-preview-slow.gif',save_all=True,append_images=gif[1:],duration=125,loop=0,disposal=2)
(OUT/'validation.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
print('PASS: 24 frames 45x58, 180x348 sheet, foreground preservation checks passed.')
print('Tail roots:',[a['tail_root'] for a in audit])

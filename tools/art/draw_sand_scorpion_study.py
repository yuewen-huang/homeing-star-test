"""Procedural silhouette study. No reference pixels or generated images are sampled.

Authored polygon facets + correlated sand shading, rasterized at native pixel size.
The JSON retains editable shapes; this is a study, not a production replacement.
"""
import json
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / 'combat-vfx-studio/studies/sandstorm_scorpion'
OUT = ROOT / 'homeing-star-test/artifacts/sandstorm-scorpion-study'
W, H = 320, 380
PAL = ['49311e', '715031', '977044', 'b88b52', 'd7aa6d', 'efd09a', 'ffe6b4']


class Drawing:
    def __init__(self):
        self.shapes = []

    def poly(self, points, shade):
        self.shapes.append(dict(points=[[round(x, 2), round(y, 2)] for x, y in points], shade=shade))

    def transform(self, points, a, b, width):
        dx, dy = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        return [(a[0]+dx*u+nx*v*width, a[1]+dy*u+ny*v*width) for u, v in points]

    def plate(self, a, b, width):
        # Shield-like plates with a chevron opening; no circles or capsule stamps.
        def p(points, shade):
            self.poly(self.transform(points, a, b, width), shade)
        p([(-.12,-.61),(.10,-1.04),(.67,-.85),(1.12,0),(.67,.88),(.12,1.03),(-.12,.55),(.06,0)], 0)
        p([(-.04,-.58),(.14,-.91),(.66,-.75),(1.02,0),(.64,.77),(.15,.90),(-.04,.49),(.14,0)], 2)
        p([(.01,-.55),(.16,-.86),(.65,-.69),(1.02,0),(.45,.06),(.12,.29)], 4)
        p([(.16,-.86),(.65,-.69),(.82,-.35),(.42,-.38),(.13,-.57)], 5)
        p([(.12,.29),(.45,.06),(1.02,0),(.64,.77),(.15,.90)], 3)
        p([(.45,.06),(.67,-.68),(.57,-.12),(1.02,0),(.66,.18)], 5)
        p([(.15,.90),(.64,.77),(1.02,0),(.72,.51),(.24,.63)], 1)

    def limb(self, points, widths):
        for i in range(len(points)-1):
            a, b = points[i:i+2]
            w0, w1 = widths[i:i+2]
            dx, dy = b[0]-a[0], b[1]-a[1]
            ll = math.hypot(dx,dy)
            n = (-dy/ll,dx/ll)
            def off(p,w): return (p[0]+n[0]*w,p[1]+n[1]*w)
            self.poly([off(a,-w0),off(b,-w1),off(b,w1),off(a,w0)],1)
            self.poly([off(a,-w0*.84),off(b,-w1*.80),b,a],4)
            self.poly([a,b,off(b,w1*.8),off(a,w0*.8)],2)
            self.poly([off(a,-w0*.78),off(b,-w1*.75),off(b,-w1*.30),off(a,-w0*.40)],5)

    def hook(self, origin, angle=0, scale=1):
        # A bulbous venom sac continuing into ONE curved, acute terminal sting.
        ca, sa = math.cos(angle), math.sin(angle)
        def p(points,shade):
            self.poly([(origin[0]+scale*(x*ca-y*sa),origin[1]+scale*(x*sa+y*ca)) for x,y in points],shade)
        p([(-12,-10),(4,-17),(18,-5),(24,15),(22,37),(10,55),(-16,68),(-3,47),(3,27),(-4,11),(-16,4)],0)
        p([(-10,-7),(4,-13),(15,-3),(20,15),(18,36),(8,52),(-12,65),(1,44),(7,26),(0,8),(-13,3)],3)
        p([(-10,-7),(3,-12),(9,0),(11,22),(4,43),(-12,65),(0,39),(1,25),(-5,9)],5)
        p([(9,0),(16,6),(20,18),(16,38),(6,53),(-12,65),(4,46),(11,24)],2)
        p([(-10,-7),(3,-12),(7,-3),(-4,1),(-13,3)],6)

    def claw(self, side):
        def p(points,shade): self.poly([(160+side*x,y) for x,y in points],shade)
        # Broad palm, deeply open pincer and two differently curved fingers.
        p([(48,272),(67,279),(85,297),(86,314),(78,335),(62,351),(39,362),(50,348),(61,332),(64,317),(52,317),(43,329),(41,345),(32,331),(32,312),(40,296),(49,289)],0)
        p([(50,276),(65,282),(80,298),(81,314),(73,333),(59,348),(43,359),(55,340),(62,325),(65,312),(51,312),(41,324),(39,337),(35,330),(36,313),(44,298),(54,288)],3)
        p([(50,276),(65,282),(80,298),(62,302),(45,315),(39,337),(35,330),(36,313),(44,298),(54,288)],4)
        p([(55,280),(65,284),(75,296),(59,297),(43,310),(40,321),(40,311),(48,297),(58,290)],5)
        p([(80,298),(81,314),(73,333),(59,348),(43,359),(62,339),(73,315),(62,302)],2)
        p([(62,302),(73,315),(62,339),(43,359),(57,340),(64,321),(65,312)],5)


def ghost():
    d = Drawing()
    for side in [-1,1]:
        for pts, widths in [([(142,211),(112,190),(95,163),(73,169),(52,195)],[8,9,8,5,0]),
                            ([(137,230),(105,216),(85,199),(49,211),(37,241)],[8,9,8,5,0]),
                            ([(137,249),(104,242),(77,235),(46,260),(38,286)],[9,10,8,4,0]),
                            ([(141,264),(115,282),(96,286),(90,302)],[10,12,10,9])]:
            d.limb([(160+side*(160-x),y) for x,y in pts], widths)
        d.claw(side)
    # Tail: a strong asymmetrical arch; segment overlap remains visible at small scale.
    points = [(159,191),(152,162),(137,132),(131,101),(143,70),(167,44),(197,29),(228,29),(253,45)]
    for i in range(len(points)-1):
        d.plate(points[i], points[i+1], [19,18,17,16,15,14,13,12][i])
    d.hook(points[-1], -.12, .82)
    for a,b,w in [((159,215),(159,191),26),((160,237),(159,213),30),((160,255),(160,235),33)]:
        d.plate(a,b,w)
    # Head carapace with an explicit central keel, cheek facets and small mandibles.
    d.poly([(132,248),(148,240),(171,240),(189,251),(194,271),(180,289),(162,307),(143,292),(128,273)],0)
    d.poly([(134,250),(148,243),(170,243),(186,253),(190,270),(178,285),(162,301),(145,289),(132,272)],3)
    d.poly([(134,250),(150,244),(160,256),(149,268),(133,270)],4)
    d.poly([(160,256),(171,244),(186,253),(189,270),(174,269)],2)
    d.poly([(133,270),(149,268),(160,256),(174,269),(189,270),(170,278),(162,298),(153,279)],5)
    d.poly([(145,254),(150,247),(157,257),(152,268)],2)
    d.poly([(168,248),(179,255),(182,266),(167,263)],4)
    d.poly([(153,275),(161,279),(171,274),(162,298)],6)
    d.poly([(145,288),(147,301),(156,309),(153,297)],1)
    d.poly([(176,288),(175,301),(166,310),(169,297)],1)
    return d


def tail(pose):
    d = Drawing()
    paths = {
        'charge': [(91,319),(61,275),(49,223),(59,168),(92,119),(139,89),(192,86),(231,113)],
        'strike': [(72,313),(50,267),(55,215),(87,169),(131,146),(179,151),(211,181),(224,221)],
        'impact': [(63,317),(43,275),(48,231),(79,196),(119,187),(158,203),(180,233),(186,264)],
    }
    pts=paths[pose]
    for i in range(len(pts)-1): d.plate(pts[i],pts[i+1],[25,24,23,22,21,19,17][i])
    d.hook(pts[-1], {'charge':-.16,'strike':.05,'impact':.24}[pose],1.0)
    if pose=='impact':
        cx,cy = 186-16*math.sin(.24),333
        for side in [-1,1]:
            def p(pts,shade): d.poly([(cx+side*x,cy+y) for x,y in pts],shade)
            p([(0,6),(16,-17),(24,-7),(40,-34),(36,-12),(70,-23),(52,-4),(93,0),(54,10),(13,12)],1)
            p([(0,3),(18,-10),(18,0),(38,-22),(30,-3),(59,-13),(42,4),(78,2),(43,10),(7,10)],4)
            p([(0,5),(18,1),(30,-10),(25,3),(46,1),(26,11),(3,11)],6)
    return d


def noise(x,y):
    def h(a,b):
        v=((a*374761393+b*668265263)^1711)&0xffffffff
        v=((v^(v>>13))*1274126177)&0xffffffff
        return (v&65535)/65535
    xx,yy=x/6,y/6
    ix,iy=math.floor(xx),math.floor(yy)
    u,v=xx-ix,yy-iy
    u=u*u*(3-2*u);v=v*v*(3-2*v)
    return ((1-u)*h(ix,iy)+u*h(ix+1,iy))*(1-v)+((1-u)*h(ix,iy+1)+u*h(ix+1,iy+1))*v


def render(d, particles=True):
    idx=Image.new('L',(W,H),0)
    draw=ImageDraw.Draw(idx)
    for poly in d.shapes: draw.polygon([tuple(p) for p in poly['points']],fill=poly['shade']+1)
    rgb=[tuple(bytes.fromhex(c)) for c in PAL]
    out=Image.new('RGBA',(W,H))
    mask=idx.point(lambda p:255 if p else 0)
    interior=mask.filter(ImageFilter.MinFilter(3))
    rnd=random.Random(173)
    for y in range(H):
        for x in range(W):
            s=idx.getpixel((x,y))-1
            if s<0: continue
            n=noise(x,y)
            # Clumped shade variation, not equally distributed bright noise.
            if interior.getpixel((x,y)) and 1<s<5:
                s=max(1,min(5,s+(1 if n>.72 else -1 if n<.27 else 0)))
            if not interior.getpixel((x,y)) and rnd.random()<.045:
                continue
            out.putpixel((x,y),rgb[s]+(255,))
    if particles:
        dd=ImageDraw.Draw(out)
        edge=[(x,y) for y in range(5,H-5) for x in range(5,W-5) if mask.getpixel((x,y)) and not interior.getpixel((x,y))]
        for x,y in rnd.sample(edge,min(150,len(edge))):
            dx,dy=rnd.randint(-10,10),rnd.randint(-8,8)
            if mask.getpixel((x+dx,y+dy)):continue
            size=rnd.choices([1,2,3],[.70,.25,.05])[0]
            dd.rectangle((x+dx,y+dy,x+dx+size-1,y+dy+size-1),fill=rgb[rnd.choice([2,3,4,5])]+(rnd.randint(110,230),))
    return out


def main():
    DEST.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    poses={'ghost':ghost(), **{name:tail(name) for name in ['charge','strike','impact']}}
    for name,d in poses.items():
        img=render(d)
        img.save(DEST/(name+'.png'));img.save(OUT/(name+'.png'))
        (DEST/(name+'.json')).write_text(json.dumps(dict(size=[W,H],palette=PAL,shapes=d.shapes),indent=2),encoding='utf-8')
    board=Image.new('RGB',(1280,900),'#202523')
    draw=ImageDraw.Draw(board)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    draw.text((32,20),'沙蝎虚影 · 纯程序造型样稿',font=font,fill='#ecd3a7')
    draw.text((32,55),'多边形甲片 / 沙色明暗 / 局部碎砂     尚未替换实战特效',font=small,fill='#a5aaa5')
    full=render(poses['ghost']).resize((640,760),Image.Resampling.NEAREST)
    board.paste(full,(0,105),full)
    mini=render(poses['ghost']);board.paste(mini,(700,110),mini)
    draw.text((725,85),'原尺寸 320 × 380',font=small,fill='#bfb69e')
    for i,name in enumerate(['charge','strike','impact']):
        im=render(poses[name]).resize((208,247),Image.Resampling.NEAREST)
        board.paste(im,(640+i*208,568),im)
        draw.text((680+i*208,835),['蓄势轮廓','下刺轮廓','触地轮廓'][i],font=small,fill='#d1bd95')
    board.save(OUT/'study_board.png')
    # Enlarged standalone preserves transparency; no white/black matte baked in.
    full.save(OUT/'ghost_enlarged.png')
    print(json.dumps(dict(output=str(OUT),polygons={k:len(v.shapes) for k,v in poses.items()})))


if __name__=='__main__': main()

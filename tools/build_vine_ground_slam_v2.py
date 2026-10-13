"""Organic pixel vines: travelling bend, tip lag, ground compression and recoil.

Offline art only. Articulated tangent poses preserve the length of the whip;
all frames share a canvas, palette and planted root. No image generation.
"""
from pathlib import Path
import argparse
import json
import math

from PIL import Image, ImageDraw, ImageFont

from build_vine_ground_slam import SIZE, ROOT, PALETTE, aseprite, ribbon, rounded

# Six tangent controls from root to tip, integrated along the SAME arc length.
# Angles are measured from upright, positive toward the right. The root acts
# first while the top remains in the previous pose; it is not a rigid rotation.
POSES = [
    [0,0,0,0,0,0], [-2,4,6,-8,-6,10], [-2,4,6,-8,-6,10],
    [-2,4,6,-8,-6,10], [-2,4,6,-8,-6,10], [-2,4,6,-8,-6,10],
    [-2,4,6,-8,-6,10], [-3,5,10,-7,-12,8], [-3,5,8,-8,-12,4],
    [-15,-18,-10,0,18,28], [-18,-28,-24,-9,18,35],
    [25,-20,-28,-18,8,32], [52,32,-15,-30,-13,22],
    [72,68,42,-8,-37,-18], [76,83,80,52,-2,-28],
    [72,86,104,94,55,-8], [48,69,87,106,112,114],
    [55,78,89,100,109,110], [55,78,89,100,108,112],
    [50,68,82,93,86,67], [47,62,71,61,36,-5],
    [45,65,82,94,101,108], [-18,45,80,105,100,96],
    [-20,-10,20,58,99,113], [-6,-14,-5,28,66,88],
    [-4,3,9,-3,8,18], [-2,4,6,-8,-6,10], [-2,4,6,-8,-6,10],
    [0,0,0,0,0,0], [0,0,0,0,0,0],
]
LENGTHS = [0,6,18,38,66,102,138,160,160,160,160,160,160,160,160,
           160,160,160,160,160,160,160,160,152,120,78,38,10,0,0]
DURATIONS = [80,60,60,60,60,60,60,80,100,90,100,50,40,40,30,
             30,100,70,70,70,60,60,60,70,70,70,60,60,80,240]
STAGES = ['01_破土生长']*8 + ['02_绷紧蓄力']*3 + ['03_根部发力_鞭梢滞后']*3 + \
         ['04_末端快甩_拍地']*5 + ['05_余劲反弹_拖回']*5 + ['06_收回地下']*6
VARIANTS = [
    {'id':'01_细藤鞭','radius':7.2,'thorns':False,'dual':False,'weight':'快甩'},
    {'id':'02_粗藤重拍','radius':11.0,'thorns':True,'dual':False,'weight':'沉重压地'},
    {'id':'03_双藤重拍','radius':6.0,'thorns':False,'dual':True,'weight':'错拍'},
]


def hermite(values,u):
    t=max(0,min(1,u))*(len(values)-1)
    i=min(len(values)-2,int(t));t-=i
    a=values[max(0,i-1)];b=values[i];c=values[i+1];d=values[min(len(values)-1,i+2)]
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)


def profile(variant,index,secondary=False):
    if secondary and 11<=index<=23:
        index=max(10,index-2)
    angles=POSES[index].copy()
    if variant['thorns']:
        # A thicker vine carries its upper mass farther behind the lower body.
        if index in (12,13,14,15):
            for k in (3,4,5):angles[k]=.7*POSES[index-1][k]+.3*angles[k]
        if index in (19,20):
            angles=[52,72,87,99,106,98] if index==19 else [50,69,82,92,85,64]
    if secondary:
        angles=[a+(5*math.sin(i*1.7)) for i,a in enumerate(angles)]
    return angles


def centerline(angles,length,origin):
    points=[tuple(map(float,origin))]
    steps=96
    for i in range(steps):
        theta=math.radians(hermite(angles,(i+.5)/steps))
        x,y=points[-1]
        points.append((x+length/steps*math.sin(theta), y-length/steps*math.cos(theta)))
    return points


def local_frame(points,i):
    a,b=points[max(0,i-1)],points[min(len(points)-1,i+1)]
    dx,dy=b[0]-a[0],b[1]-a[1]
    n=max(.001,math.hypot(dx,dy))
    return (dx/n,dy/n),(-dy/n,dx/n)


def draw_leaf(draw,p,tangent,normal,sign,size=1):
    tx,ty=tangent;nx,ny=normal
    # Asymmetric pointed leaf clusters, attached along the moving body tangent.
    def point(a,b):return rounded((p[0]+tx*a+nx*b*sign,p[1]+ty*a+ny*b*sign))
    polygon=[point(0,0),point(-3*size,5*size),point(-2*size,11*size),
             point(4*size,8*size),point(5*size,3*size)]
    draw.polygon(polygon,fill=PALETTE[0])
    draw.polygon([point(0,1),point(-1,8*size),point(3*size,6*size),point(3*size,2)],fill=PALETTE[2])
    draw.line([point(0,0),point(1,7*size)],fill=PALETTE[3],width=1)


def draw_vine(im,points,radius,variant,length,phase=0):
    d=ImageDraw.Draw(im)
    n=len(points)-1
    radii=[]
    for i in range(n+1):
        u=i/n
        irregular=1+.14*math.sin(u*17+.5)+.10*math.sin(u*29+1.2)
        bulge=.22*math.exp(-((u-.18)/.08)**2)+.20*math.exp(-((u-.49)/.07)**2)
        radii.append(max(.85,radius*(1-u)**.85*(irregular+bulge)))
    d.polygon(ribbon(points,radii,1),fill=PALETTE[0])
    d.polygon(ribbon(points,radii),fill=PALETTE[1])
    # Two continuous strands entwine along the vine. Front/back changes create
    # broad longitudinal interlocks, not evenly spaced transverse bamboo joints.
    strand_paths=[[],[]]
    for i,p in enumerate(points):
        _,normal=local_frame(points,i)
        displacement=math.sin(i/n*math.tau*2.15+phase)*radii[i]*.58
        for strand,sign in enumerate((-1,1)):
            strand_paths[strand].append((p[0]+normal[0]*displacement*sign,
                                         p[1]+normal[1]*displacement*sign))
    d.polygon(ribbon(strand_paths[0],[r*.47 for r in radii]),fill=PALETTE[2])
    # Alternate the front strand in wide organic patches; retain a dark seam.
    for start,end in ((0,.18),(.31,.55),(.77,.97)):
        a,b=round(start*n),round(end*n)
        d.polygon(ribbon(strand_paths[1][a:b+1],[r*.53 for r in radii[a:b+1]]),fill=PALETTE[2])
        if b-a>4:
            d.line([rounded(p) for p in strand_paths[1][a+2:b-1]],fill=PALETTE[3],width=1)
    # Short diagonal bark facets at the rooted foot; no horizontal rings.
    if length>35:
        d.polygon(ribbon(points[:10],[r*.40 for r in radii[:10]],offset=-radius*.35),fill=PALETTE[4])
    for u,sign in ((.26,-1),(.61,1),(.82,-1)):
        i=round(u*n)
        if length*u<18:continue
        p=points[i];tangent,normal=local_frame(points,i)
        if variant['thorns']:
            tx,ty=tangent;nx,ny=normal
            base=(p[0]+nx*sign*radii[i]*.6,p[1]+ny*sign*radii[i]*.6)
            tip=(base[0]+nx*sign*7-tx*3,base[1]+ny*sign*7-ty*3)
            d.polygon([rounded((base[0]-tx*3,base[1]-ty*3)),rounded(tip),
                       rounded((base[0]+tx*3,base[1]+ty*3))],fill=PALETTE[0])
            d.line([rounded(base),rounded(tip)],fill=PALETTE[2],width=2)
            if u==.61:draw_leaf(d,p,tangent,normal,-sign,.7)
        elif u!=.82:
            draw_leaf(d,p,tangent,normal,sign,1 if u<.5 else .8)


def variant_duration(variant,index):
    ms=DURATIONS[index]
    if variant['thorns'] and index in (10,16,17,18):ms+=40
    if not variant['thorns'] and not variant['dual'] and index in (17,18):ms-=20
    return ms


def soil(im,index,variant):
    d=ImageDraw.Draw(im);x,y=ROOT
    if index==29:return
    d.polygon([(x-14,y+3),(x-10,y-1),(x-5,y-3),(x+3,y-2),
               (x+9,y-4),(x+16,y+2),(x+10,y+4)],fill=PALETTE[4])
    d.polygon([(x-9,y),(x-5,y-2),(x+1,y-1),(x+3,y+1)],fill=PALETTE[5])
    d.line([(x+5,y+1),(x+10,y-1),(x+12,y)],fill=PALETTE[5],width=1)


def impact(im,points,age,variant):
    d=ImageDraw.Draw(im)
    x=max(120,min(207,round(points[-1][0])));y=ROOT[1]
    strength=1.3 if variant['thorns'] else 1
    # The ground contact stays fixed while clods travel outwards after impact.
    if age==0:
        d.polygon([(x-20,y),(x-11,y-3),(x-5,y-10),(x,y-3),(x+5,y-7),
                   (x+10,y),(x+7,y+2),(x-15,y+2)],fill=PALETTE[5])
        d.line([(x-8,y-1),(x-5,y-7),(x-2,y-1)],fill=PALETTE[3],width=2)
    d.line([(x-28-age*2,y+1),(x-16,y),(x-8,y+2),(x+8,y)],fill=PALETTE[4],width=2)
    for j in range(5 if variant['thorns'] else 3):
        px=x-22+j*9+(j-2)*age*3
        py=y-4-abs(j-1)*2-age*7+age*age*2
        if 3<=px<=218:
            d.polygon([(px,py),(px+3,py-1),(px+4,py+2),(px+1,py+3)],fill=PALETTE[5 if j%2 else 4])
    if age in (1,2):
        # A couple of detached leaves sell the abrupt stop of a living vine.
        for j in range(2):
            px=x-42+j*24+age*(j*2-3)*4
            py=y-18-age*4-j*8
            d.polygon([(px,py),(px+5,py-2),(px+4,py+2)],fill=PALETTE[2])


def paint(variant,index):
    im=Image.new('RGBA',SIZE)
    soil(im,index,variant)
    length=LENGTHS[index]
    primary=[];secondary=[]
    if length:
        if variant['dual']:
            secondary=centerline(profile(variant,index,True),length*.91,(ROOT[0]-4,ROOT[1]))
            primary=centerline(profile(variant,index),length,(ROOT[0]+4,ROOT[1]))
        else:primary=centerline(profile(variant,index),length,ROOT)
        # Ground contact clamps only the final whip tip after it reaches the
        # floor, leaving the recoil pose and upstream wave intact.
        if 16<=index<=18:
            primary=[(x,min(ROOT[1]-1,y)) for x,y in primary]
        if variant['dual'] and 18<=index<=20:
            secondary=[(x,min(ROOT[1]-1,y)) for x,y in secondary]
        if secondary:
            draw_vine(im,secondary,variant['radius']*.9,variant,length,1.8)
        draw_vine(im,primary,variant['radius'],variant,length,.4)
    if 16<=index<=18 and primary:impact(im,primary,index-16,variant)
    if variant['dual'] and 18<=index<=20 and secondary:impact(im,secondary,index-18,variant)
    # A curved smear follows the actual tip travel, rather than an arbitrary
    # circular arc. It is restricted to the final two fast release cels.
    if index in (14,15) and primary:
        old=centerline(profile(variant,index-1),160,ROOT)
        d=ImageDraw.Draw(im)
        for k in (0,1):
            d.line([rounded((p[0]-3-k*3,p[1]+3+k*2)) for p in old[-18:]],fill=PALETTE[2],width=1)
    bounds=im.getbbox()
    assert bounds is None or (bounds[0]>0 and bounds[1]>0 and bounds[2]<SIZE[0] and bounds[3]<SIZE[1]),(variant['id'],index,bounds)
    return im,primary


def save_gif(path,frames,durations):
    # Palette includes every effect colour, not only a selected keyframe.
    pal=Image.new('P',(1,1))
    colors=[(27,33,28),(72,83,66),(218,232,204)]+[c[:3] for c in PALETTE]
    pal.putpalette([v for color in colors for v in color]+[0]*(768-len(colors)*3))
    indexed=[f.quantize(palette=pal,dither=Image.Dither.NONE) for f in frames]
    indexed[0].save(path,save_all=True,append_images=indexed[1:],duration=durations,loop=0,disposal=2,optimize=False)
    with Image.open(path) as im:
        total=0
        for i in range(im.n_frames):im.seek(i);total+=im.info['duration']
        assert total==sum(durations)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path);args=parser.parse_args()
    out=args.output;out.mkdir(parents=True,exist_ok=True)
    preview=out/'预览';preview.mkdir(exist_ok=True)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',21)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',14)
    metadata={'version':2,'canvas':SIZE,'pivot':ROOT,'palette':PALETTE,'direction':'向右',
              'layers':['参考_隐藏锁定','藤鞭_可编辑'],'variants':[]}
    clips=[]
    assert POSES[11][0]-POSES[10][0]>=40 and abs(POSES[11][-1]-POSES[10][-1])<=3
    crossing=[next(i for i in range(11,17) if POSES[i][k]>50) for k in (0,2,5)]
    assert crossing[0]<crossing[1]<crossing[2]
    for variant in VARIANTS:
        images=[];frame_plan=[];rendered=[]
        folder=out/'序列帧'/variant['id'];folder.mkdir(parents=True,exist_ok=True)
        durations=[variant_duration(variant,i) for i in range(30)]
        plan=[(LENGTHS[i],POSES[i][0],durations[i],STAGES[i]) for i in range(30)]
        for i in range(30):
            image,points=paint(variant,i)
            images.append(image)
            colors={p for p in image.get_flattened_data() if p[3]}
            assert colors<=set(PALETTE)
            assert set(image.getchannel('A').get_flattened_data())<={0,255}
            image.save(folder/f'{i:02d}.png')
            frame_plan.append({'frame':i,'duration_ms':durations[i],'stage':STAGES[i],
                'length':LENGTHS[i],'tangent_angles':profile(variant,i),
                'tip':rounded(points[-1]) if points else ROOT})
            bg=Image.new('RGBA',SIZE,(27,33,28,255))
            ImageDraw.Draw(bg).line((0,ROOT[1],SIZE[0],ROOT[1]),fill=(72,83,66,255))
            bg.alpha_composite(image)
            rendered.append(bg.convert('RGB').resize((448,448),Image.Resampling.NEAREST))
        atlas=Image.new('RGBA',(224*30,224))
        for i,image in enumerate(images):atlas.paste(image,(224*i,0))
        atlas.save(folder/'strip.png')
        ref=images[7].copy()
        ImageDraw.Draw(ref).line((5,196,218,196),fill=(120,130,120,180))
        tags=aseprite(out/(variant['id']+'.aseprite'),images,ref,plan)
        save_gif(preview/(variant['id']+'.gif'),rendered,durations)
        save_gif(preview/(variant['id']+'_慢放.gif'),rendered,[v*2 for v in durations])
        clips.append(rendered)
        metadata['variants'].append({'file':variant['id']+'.aseprite','frames':30,
            'duration_ms':sum(durations),'tags':tags,'frame_plan':frame_plan,'character':variant['weight']})
    compare=[]
    # The combined GIF uses the heavy clip's holds; per-variant GIFs and Aseprite
    # preserve the deliberately different authored weight timings.
    combined_durations=[max(variant_duration(v,i) for v in VARIANTS) for i in range(30)]
    for i in range(30):
        bg=Image.new('RGB',(1344,488),(27,33,28));d=ImageDraw.Draw(bg)
        for j,variant in enumerate(VARIANTS):
            bg.paste(clips[j][i],(448*j,40))
            d.text((448*j+16,5),variant['id']+' · '+variant['weight'],font=font,fill=(218,232,204))
        compare.append(bg)
    save_gif(preview/'三种变体对照.gif',compare,combined_durations)
    selected=[7,10,11,12,13,14,15,16,18,22]
    sheet=Image.new('RGB',(224*len(selected),270*3),(27,33,28));d=ImageDraw.Draw(sheet)
    for j,variant in enumerate(VARIANTS):
        for k,i in enumerate(selected):
            sheet.paste(clips[j][i].resize(SIZE,Image.Resampling.NEAREST),(224*k,270*j+30))
            d.text((224*k+5,270*j+5),f'{variant["id"]} F{i:02d}',font=small,fill=(218,232,204))
    sheet.save(preview/'传力关键帧总览.png')
    # Root-to-tip vector overlay is only an external diagnostic, never a layer
    # in the artist's two-layer Aseprite file.
    diag=Image.new('RGB',(448*4,488),(27,33,28));d=ImageDraw.Draw(diag)
    for col,i in enumerate((11,12,13,15)):
        diag.paste(clips[0][i],(448*col,40))
        points=centerline(POSES[i],160,ROOT)
        for u in (0,.5,.92):
            k=round(u*96);p=points[k]
            t,n=local_frame(points,k)
            x=448*col+p[0]*2;y=40+p[1]*2
            d.line((x,y,x+t[0]*24,y+t[1]*24),fill=(218,232,204),width=2)
        d.text((448*col+10,5),f'F{i:02d}: 根 {POSES[i][0]}° / 梢 {POSES[i][-1]}°',font=small,fill=(218,232,204))
    diag.save(preview/'根到梢传力检查.png')
    (out/'时间轴.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'验收说明.md').write_text('''# 活藤重拍 v2 · 惯性与造型重做

三份 Aseprite 各 30 帧，保持 224×224 透明画布和地底枢轴 (48,196)，统一向右拍打。
每帧六色、二值透明度，无抗锯齿或抖色。仅参考层（隐藏锁定）及特效层（独立可编辑帧）。

造型由两股粗细不匀的藤肉交缠，带不对称叶片、根部木质和少量短刺；去掉直杆与横向等距竹节。
F00–07 垂直生长；F08–10 绷紧蓄力；F11–13 根部先发力，上段滞后反弯；F14–18 鞭梢追上、快甩拍地、压地停顿；F19–23 余劲反弹并由根部拖回；F24–29 收入地下。
根、中段、鞭梢的切线转向独立，弯曲波逐段传播；全长期间沿弧长积分保持 160 像素，不整根同步旋转。

01 细藤：释放快、拍地保持较短。02 粗藤：上段滞后更多、蓄力和压地保持更长、反弹更低。03 双藤：第二根滞后两帧，分别拍地。
每份原速 GIF 使用自己的时长；对照 GIF 采用三者最长停顿以便横向比较。
另有 0.5× 慢放 GIF、关键帧总览和外部传力检查图，诊断内容未塞进 Aseprite 图层。

这批仅用于离线美术验收，不接入游戏。旧 v1 保留原样。
制作脚本：homeing-star-test/tools/build_vine_ground_slam_v2.py。
''',encoding='utf-8')
    print(json.dumps({'output':str(out),'frames_each':30,'release_crossing_frames':crossing,
                      'clips':[(v['file'],v['duration_ms']) for v in metadata['variants']]},ensure_ascii=True))


if __name__=='__main__':main()

"""Make three deterministic pixel-art ground-vine slam Aseprite handoffs.

This is an offline art deliverable; it does not touch game code or resources.
"""
from pathlib import Path
import argparse
import json
import math
import struct
import zlib

from PIL import Image, ImageDraw, ImageFont

from package_deer_vfx_aseprite import chunk, string, user_data
from aseprite_rgba_reader import read, layer_frame

SIZE = (224, 224)
ROOT = (48, 196)
PALETTE = [
    (23, 43, 25, 255), (47, 80, 34, 255),
    (88, 128, 49, 255), (163, 190, 94, 255),
    (99, 69, 43, 255), (158, 116, 65, 255),
]
# length, angle from vertical (right positive), duration ms, stage
PLAN = [
    (0, 0, 90, '01_破土生长'), (8, 0, 60, '01_破土生长'),
    (22, 0, 60, '01_破土生长'), (48, 0, 60, '01_破土生长'),
    (80, 0, 60, '01_破土生长'), (120, 0, 60, '01_破土生长'),
    (160, 0, 70, '01_破土生长'),
    (160, 0, 110, '02_蓄力'), (160, -9, 80, '02_蓄力'),
    (160, -14, 80, '02_蓄力'),
    (160, 12, 50, '03_重拍'), (160, 49, 40, '03_重拍'),
    (160, 80, 40, '03_重拍'), (160, 90, 90, '03_重拍'),
    (156, 90, 70, '03_重拍'),
    (150, 77, 60, '04_回收'), (143, 55, 60, '04_回收'),
    (118, 30, 60, '04_回收'), (84, 12, 60, '04_回收'),
    (48, 0, 60, '04_回收'), (15, 0, 60, '04_回收'),
    (0, 0, 180, '04_回收'),
]
VARIANTS = [
    {'id': '01_细藤鞭', 'radius': 4.0, 'leaf': True, 'thorn': False, 'dual': False},
    {'id': '02_粗藤重拍', 'radius': 8.0, 'leaf': False, 'thorn': True, 'dual': False},
    {'id': '03_双藤重拍', 'radius': 4.3, 'leaf': True, 'thorn': False, 'dual': True},
]


def rounded(p):
    return (round(p[0]), round(p[1]))


def bezier(points, t):
    u = 1 - t
    weights = [u**3, 3*u*u*t, 3*u*t*t, t**3]
    return tuple(sum(p[c]*w for p, w in zip(points, weights)) for c in (0, 1))


def vine_curve(length, angle, origin, variation=0.0):
    x, y = origin
    theta = math.radians(angle)
    s, c = math.sin(theta), math.cos(theta)
    # The base keeps pointing out of the soil, while the upper half bends and
    # accelerates toward the ground. This is a flexing whip, not a rigid pole.
    tip = (x + length*s, y - max(0.0, length*c))
    p1 = (x + length*s*0.08, y - length*(0.34*c + 0.22*max(0, s)))
    p2 = (x + length*s*0.68 + variation, y - length*(0.80*c + 0.18*max(0, s)))
    if abs(angle) < 0.001:
        p1 = (x, y-length*0.33)
        p2 = (x+variation, y-length*0.75)
    return [origin, p1, p2, tip]


def ribbon(points, radii, extra=0.0, offset=0.0):
    left, right = [], []
    for i, (p, r) in enumerate(zip(points, radii)):
        a, b = points[max(0, i-1)], points[min(len(points)-1, i+1)]
        dx, dy = b[0]-a[0], b[1]-a[1]
        norm = max(0.001, math.hypot(dx, dy))
        nx, ny = -dy/norm, dx/norm
        r = max(0.6, r+extra)
        left.append(rounded((p[0]+nx*(r+offset), p[1]+ny*(r+offset))))
        right.append(rounded((p[0]+nx*(-r+offset), p[1]+ny*(-r+offset))))
    return left + right[::-1]


def stem(im, curve, radius, variant, length):
    draw = ImageDraw.Draw(im)
    points = [bezier(curve, i/60) for i in range(61)]
    radii = [max(0.8, radius*(1-i/64)**0.6) for i in range(61)]
    draw.polygon(ribbon(points, radii, 1), fill=PALETTE[0])
    draw.polygon(ribbon(points, radii), fill=PALETTE[1])
    draw.polygon(ribbon(points, [r*0.50 for r in radii], offset=radius*0.25), fill=PALETTE[2])
    # One short highlight cluster at each natural stem joint.
    for t in (0.25, 0.57, 0.83):
        if length*t < 12:
            continue
        i = round(t*60)
        a, b = points[max(0, i-2)], points[min(60, i+2)]
        draw.line([rounded(a), rounded(b)], fill=PALETTE[3], width=1)
        p = points[i]
        a, b = points[max(0, i-1)], points[min(60, i+1)]
        dx, dy = b[0]-a[0], b[1]-a[1]
        n = max(.001, math.hypot(dx, dy))
        nx, ny = -dy/n, dx/n
        if variant['thorn']:
            sign = -1 if i % 2 else 1
            q = (p[0]+nx*sign*(radii[i]+6), p[1]+ny*sign*(radii[i]+6))
            draw.polygon([rounded(a), rounded(q), rounded(b)], fill=PALETTE[0])
            draw.line([rounded(p), rounded(q)], fill=PALETTE[3], width=2)
        elif variant['leaf'] and t < .8:
            sign = 1 if t < .4 else -1
            q = (p[0]+nx*sign*9, p[1]+ny*sign*9-2)
            draw.polygon([rounded(p), rounded((q[0]-2, q[1]-3)), rounded((q[0]+3, q[1]-1)), rounded((q[0]+1, q[1]+3))], fill=PALETTE[2])
            draw.line([rounded(p), rounded(q)], fill=PALETTE[3], width=1)


def paint(variant, index):
    length, angle, _, _ = PLAN[index]
    im = Image.new('RGBA', SIZE)
    d = ImageDraw.Draw(im)
    if index == len(PLAN)-1:
        return im
    # Small, restrained soil clumps stay on the shared ground anchor.
    rootx, ground = ROOT
    width = 10 if not variant['dual'] else 14
    d.polygon([(rootx-width,ground+2),(rootx-width+3,ground-1),(rootx-3,ground-3),
               (rootx+5,ground-2),(rootx+width,ground+2)], fill=PALETTE[4])
    d.line([(rootx-width+3,ground),(rootx-3,ground-2),(rootx+6,ground)], fill=PALETTE[5], width=1)
    if length:
        if variant['dual']:
            previous = PLAN[max(0, index-1)]
            secondary_angle = previous[1] if index >= 10 else angle+2
            secondary_length = min(length, previous[0]+12)*0.9
            stem(im, vine_curve(secondary_length, secondary_angle, (rootx-3,ground), -6), 3.6, variant, secondary_length)
            stem(im, vine_curve(length, angle, (rootx+3,ground), 5), variant['radius'], variant, length)
        else:
            stem(im, vine_curve(length, angle, ROOT, -3 if variant['thorn'] else 2), variant['radius'], variant, length)
    # Fast, thin motion accents only on the two transit frames.
    if index in (11,12):
        a = math.radians(angle-12)
        r = length-14
        for offset in (0,5):
            arc = []
            for k in range(9):
                th = a + math.radians(k*2)
                arc.append(rounded((rootx+(r+offset)*math.sin(th),ground-(r+offset)*math.cos(th))))
            d.line(arc,fill=PALETTE[2],width=1)
    if index in (13,14,15):
        age = index-13
        impactx = rootx+155
        d.line([(impactx-24-age*3,ground+1),(impactx-13,ground-1),(impactx,ground+1),
                (impactx+12,ground)],fill=PALETTE[5],width=2 if age==0 else 1)
        for j in range(4 if variant['thorn'] else 3):
            px = impactx-25+j*11+age*(j-2)*3
            py = ground-5-age*4-(j%2)*5
            d.rectangle((px,py,px+2,py+2),fill=PALETTE[5 if j%2 else 4])
        if age == 0:
            d.line([(impactx-12,ground),(impactx-9,ground-7),(impactx-6,ground-1)],fill=PALETTE[3],width=2)
    return im


def aseprite(path, images, reference, plan=None):
    plan = PLAN if plan is None else plan
    pack = struct.pack
    initial=[]
    for name,flags in [('参考_隐藏锁定',0),('藤鞭_可编辑',3)]:
        initial.append(chunk(0x2004,pack('<6HB3x',flags,0,0,0,0,0,255)+string(name)))
    initial.append(user_data(f'所有特效帧独立；参考层默认隐藏。地底枢轴 {ROOT}。'))
    tags=[{'name':'全动作','from':0,'to':len(images)-1}]
    for stage in dict.fromkeys(p[3] for p in plan):
        ids=[i for i,p in enumerate(plan) if p[3]==stage]
        tags.append({'name':stage,'from':min(ids),'to':max(ids)})
    body=pack('<H8x',len(tags))
    for tag in tags:
        body+=pack('<HHB8x3BB',tag['from'],tag['to'],0,100,155,70,0)+string(tag['name'])
    initial.append(chunk(0x2018,body))
    initial.append(chunk(0x2022,pack('<III',1,2,0)+string('ground_origin')+pack('<IiiIIii',0,0,0,*SIZE,*ROOT)))
    palette=pack('<III8x',len(PALETTE),0,len(PALETTE)-1)
    for color in PALETTE:
        palette+=pack('<H4B',0,*color)
    initial.append(chunk(0x2019,palette))
    blocks=[]
    for i,image in enumerate(images):
        chunks=initial.copy() if i==0 else []
        reference_frame = reference[i] if isinstance(reference, (list, tuple)) else reference
        for layer,celimage in enumerate((reference_frame,image)):
            bbox=celimage.getbbox()
            x,y=bbox[:2] if bbox else (0,0)
            crop=celimage.crop(bbox) if bbox else Image.new('RGBA',(1,1))
            # Every editable effect cel has its own compressed RGBA payload.
            cel=pack('<HhhBHh5xHH',layer,x,y,255,2,0,*crop.size)+zlib.compress(crop.tobytes())
            chunks.append(chunk(0x2005,cel))
        payload=b''.join(chunks)
        blocks.append(pack('<IHHH2xI',16+len(payload),0xF1FA,len(chunks),plan[i][2],len(chunks))+payload)
    header=bytearray(128)
    struct.pack_into('<I5HIH',header,0,128+sum(map(len,blocks)),0xA5E0,len(images),*SIZE,32,1,60)
    struct.pack_into('<H',header,32,len(PALETTE))
    header[34:36]=bytes((1,1))
    path.write_bytes(bytes(header)+b''.join(blocks))
    document=read(path)
    assert document['canvas']==SIZE and len(document['layers'])==2
    assert [f['duration_ms'] for f in document['frames']]==[p[2] for p in plan]
    for i,expected in enumerate(images):
        actual,alpha=layer_frame(document,i,1)
        assert actual.tobytes()==expected.tobytes() and alpha==1
    return tags


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    out=args.output
    out.mkdir(parents=True,exist_ok=True)
    preview=out/'预览';preview.mkdir(exist_ok=True)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
    metadata={'canvas':SIZE,'pivot':ROOT,'palette':[list(c) for c in PALETTE],
              'direction':'向右重拍','layers':['参考_隐藏锁定','藤鞭_可编辑'],'variants':[]}
    clips=[]
    for variant in VARIANTS:
        images=[paint(variant,i) for i in range(len(PLAN))]
        colors={p for im in images for p in im.get_flattened_data() if p[3]}
        assert colors<=set(PALETTE)
        assert all(set(im.getchannel('A').get_flattened_data())<={0,255} for im in images)
        folder=out/'序列帧'/variant['id'];folder.mkdir(parents=True,exist_ok=True)
        for i,im in enumerate(images):im.save(folder/f'{i:02d}.png')
        atlas=Image.new('RGBA',(SIZE[0]*len(images),SIZE[1]))
        for i,im in enumerate(images):atlas.paste(im,(i*SIZE[0],0))
        atlas.save(folder/'strip.png')
        reference=images[6].copy()
        rd=ImageDraw.Draw(reference)
        rd.line((8,ROOT[1],SIZE[0]-8,ROOT[1]),fill=(120,130,120,180))
        tags=aseprite(out/(variant['id']+'.aseprite'),images,reference)
        frames=[]
        for i,im in enumerate(images):
            canvas=Image.new('RGBA',SIZE,(27,33,28,255))
            d=ImageDraw.Draw(canvas);d.line((0,ROOT[1],SIZE[0],ROOT[1]),fill=(72,83,66,255))
            canvas.alpha_composite(im)
            canvas=canvas.convert('RGB').resize((448,448),Image.Resampling.NEAREST)
            frames.append(canvas)
        pal=frames[6].quantize(colors=256)
        gif=[f.quantize(palette=pal,dither=Image.Dither.NONE) for f in frames]
        gif[0].save(preview/(variant['id']+'.gif'),save_all=True,append_images=gif[1:],duration=[p[2] for p in PLAN],loop=0,disposal=2,optimize=False)
        with Image.open(preview/(variant['id']+'.gif')) as g:
            # GIF may merge identical hold cels; preserve total authored time.
            total=0
            for i in range(g.n_frames):
                g.seek(i);total+=g.info['duration']
            assert total==sum(p[2] for p in PLAN)
        sheet=Image.new('RGB',(448*5,490*5),(27,33,28))
        sd=ImageDraw.Draw(sheet)
        for i,f in enumerate(frames):
            x=(i%5)*448;y=(i//5)*490
            sd.text((x+8,y+4),f'F{i:02d} · {PLAN[i][3][3:]} · {PLAN[i][2]}ms',font=small,fill=(210,226,197))
            sheet.paste(f,(x,y+32))
        sheet.save(preview/(variant['id']+'_逐帧.png'))
        clips.append(frames)
        metadata['variants'].append({'file':variant['id']+'.aseprite','frames':len(images),'duration_ms':sum(p[2] for p in PLAN),'tags':tags,'frame_plan':[{'frame':i,'duration_ms':p[2],'stage':p[3],'length':p[0],'angle':p[1]} for i,p in enumerate(PLAN)]})
    comparison=[]
    for i in range(len(PLAN)):
        canvas=Image.new('RGB',(448*3,488),(27,33,28))
        d=ImageDraw.Draw(canvas)
        for j,variant in enumerate(VARIANTS):
            canvas.paste(clips[j][i],(448*j,40))
            d.text((448*j+16,6),variant['id'],font=font,fill=(218,232,204))
        comparison.append(canvas)
    pal=comparison[6].quantize(colors=256)
    gif=[f.quantize(palette=pal,dither=Image.Dither.NONE) for f in comparison]
    gif[0].save(preview/'三种变体对照.gif',save_all=True,append_images=gif[1:],duration=[p[2] for p in PLAN],loop=0,disposal=2,optimize=False)
    # Small contact sheet for visual review of rise, wind-up, impact and recovery.
    selected=[3,6,9,11,13,16,19]
    board=Image.new('RGB',(224*len(selected),270*3),(27,33,28))
    d=ImageDraw.Draw(board)
    for j,variant in enumerate(VARIANTS):
        for k,i in enumerate(selected):
            d.text((224*k+8,270*j+6),f'{variant["id"]} / F{i:02d}',font=small,fill=(218,232,204))
            board.paste(clips[j][i].resize(SIZE,Image.Resampling.NEAREST),(224*k,270*j+30))
    board.save(preview/'关键帧总览.png')
    (out/'时间轴.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'验收说明.md').write_text('''# 地底藤鞭重拍：三种变体

三份 `.aseprite` 各 22 帧，透明画布 224×224，统一地底枢轴 (48,196)，统一向右。
01 细藤鞭带少量叶片；02 粗藤增加体积和短刺；03 双藤错一帧拍下。
全部为六色硬像素，透明度只有 0/255，无抖色或抗锯齿。每帧使用同一坐标系，无逐帧缩放。

动画标签：破土生长 F00–06，蓄力 F07–09，重拍 F10–14，回收 F15–21。
先垂直出土，再短暂向反方向蓄力，快速向右拍地，停顿后反弹并退回地下。
速度已写入每帧时长，整段 1.56 秒。GIF 为循环验收预览，预览地面和背景不在特效层。

仅两层：`参考_隐藏锁定`（默认隐藏、锁定，合并直立形态及地面参考）；`藤鞭_可编辑`（全部独立 RGBA 帧）。
`ground_origin` 切片保存根部 pivot。打开后可直接编辑特效层，不用删除一堆参考层。

`序列帧/` 含透明 PNG 单帧及横条，`预览/` 含单独 GIF、三种对照与关键帧总览。
脚本：测试仓库 `tools/build_vine_ground_slam.py`。当前仅是离线素材验收，不接入游戏。
''',encoding='utf-8')
    print(json.dumps({'output':str(out),'files':[v['file'] for v in metadata['variants']],'frames_each':len(PLAN),'duration_ms':sum(p[2] for p in PLAN),'native_roundtrip':'all RGBA frames exact'},ensure_ascii=True))


if __name__=='__main__':main()

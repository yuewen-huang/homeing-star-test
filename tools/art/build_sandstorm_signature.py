"""Author editable Studio swarms; all particles are baked by its native renderer."""
import json, math, random, shutil
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
STUDIO=ROOT/'combat-vfx-studio/combos'
GAME=ROOT/'homeing-star-game/assets/bosses/sandstorm_fighter'
RAMP=['30231d','62452d','9e754a','c9a372','dec496']
BASE=dict(t=0,do='swarm',material='sand',form='stream',at=[640,360],
          count=8000,size=.85,sand_grain=.6,sand_dust=.85,sand_settle=0,sand_floor=2000,
          look='mirror',ramp=RAMP,swirl=9,turbulence=10,tumble=0,
          fade_in=.035,fade_out=.18,time=0,travel=.08,linger=.32,
          length=1.,hold_path_end=True,stream_flow=.8,stream_curl=1.,stream_edge=25,width=25)

def stream(name,points,**kw):
    return dict(BASE,id=name,path=[[640+x,360+y] for x,y in points],**kw)

def write(key,title,events,cell,origin,frames):
    folder=STUDIO/('sandstorm_signature_'+key);folder.mkdir(parents=True,exist_ok=True)
    fps=60 if key=='scorpion' else 30
    doc=dict(name=title,events=events,bake=dict(cell=cell,origin=origin,frames=frames if fps==60 else math.ceil(frames/2),fps=fps,start_frame=2 if key=='slam_impact' else 0))
    style=dict(language='zh',renderer='quake',quake_style='pixel',quake_detail='fine',pixel=1,title=title)
    for name,data in [('combo',doc),('style',style)]:
        (folder/(name+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (folder/'prompt.md').write_text(title+'。原生 Studio 沙漠群体：连续翻卷、边缘散粒，暗赭沙体与浅砂高光；仅装饰，不新增命中、金光预警或游戏时钟。\n',encoding='utf-8')
    (folder/(folder.name+'.tscn')).write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/'+folder.name+'/combo.json"\nstyle_file = "res://combos/'+folder.name+'/style.json"\n',encoding='utf-8')

def main():
    # Two overlapping shear sheets follow the heel-to-toe sweep. No blade core.
    kick=[]
    for i,(width,count) in enumerate([(27,12000),(13,6000)]):
        points=[(44+132*math.sin(k/11*1.65),-67+98*k/11+i*8) for k in range(12)]
        event=stream('kick_'+str(i),points)
        event.update(width=width,count=count,travel=.095+i*.025,linger=.25,stream_edge=36,
                     size=.7,fade_out=.22,stream_flow=1.1,stream_curl=1.2,sand_dust=.30 if i else .65,
                     ramp=['201c19','594632','aa8655','d9bd8f','efdbc0'] if i else RAMP)
        kick.append(event)
    for i in range(4):
        pts=[(55+160*k/11,-35+(i-1.5)*26*k/11+13*math.sin(k/11*5+i)) for k in range(12)]
        event=stream('kick_filament_'+str(i),pts)
        event.update(count=1800,sand_dust=.10,sand_grain=1.0,width=4+i,stream_edge=15,
                     travel=.14+i*.015,linger=.19,fade_out=.22,stream_flow=0,stream_taper=.4)
        kick.append(event)
    write('kick','蝎女 · 鞭腿沙暴风压',kick,[512,320],[192,160],30)

    arrival=[]
    for side in [-1,1]:
        pts=[(side*(120*(1-k/11)**1.6),-65+105*k/11) for k in range(12)]
        event=stream('arrival_'+str(side),pts)
        event.update(count=4500,width=14,stream_edge=24,travel=.13,linger=.16,fade_out=.14,stream_flow=0)
        arrival.append(event)
    write('arrival','蝎女 · 收沙现身',arrival,[384,320],[192,160],24)

    poses=[('knee','thomas_knee_256x256_30f.png',17,(150,111)),
           ('roll','backflip_256x256_14f.png',6,(165,80)),
           ('kick','aerial_kick_256x256_15f.png',7,(103,169))]
    # Resolve the actual backflip atlas name, rather than rely on a guessed suffix.
    for key,filename,frame,hip in poses:
        if key=='roll': filename=next(p.name for p in (GAME/'body').glob('*') if 'back' in p.name and p.suffix=='.png')
        sheet=Image.open(GAME/'body'/filename).convert('RGBA'); cols=sheet.width//256
        tile=sheet.crop((frame%cols*256,frame//cols*256,(frame%cols+1)*256,(frame//cols+1)*256))
        pixels=tile.load(); points=[(x,y) for y in range(0,256,2) for x in range(0,256,2) if pixels[x,y][3]>128]
        samples=random.Random(411).sample(points,64)
        seg=[[round((x-hip[0])*1.1862,2),round((y-hip[1])*1.1862,2),1,0,3,3] for x,y in samples]
        event=dict(BASE); event.update(id='peel_'+key,form='peel',count=6000,peel_segments=seg,
            sand_dust=.1,size=.8,sand_grain=.8,time=.18,travel=0,linger=.20,fade_in=.015,fade_out=.20,turbulence=16)
        write('peel_'+key,'蝎女 · 沙躯剥离 '+key,[event],[384,384],[192,192],30)

    build_scorpion()
    print('Authored seven editable signature effects')

def build_scorpion():
    # Five broad, bounded plates with visible narrow joints. No continuous tube
    # underneath them: the silhouette itself carries the segmentation.
    raised=[(-22,42),(-137,-4),(-181,-121),(-111,-226),(13,-234),(91,-149)]
    landed=[(-24,180),(-119,140),(-166,55),(-132,-30),(-51,-6),(-8,100)]
    events=[]
    def pose_path(points): return [[640+x,360+y] for x,y in points]
    def piece(name,kind,before,after,width,count=14000,ramp=RAMP):
        a=dict(BASE);a.update(id=name,form=kind,path=pose_path(before),width=width,count=count,
            size=.9,sand_grain=.65,sand_dust=0,stream_edge=0,stream_flow=0,stream_curl=0,
            turbulence=2,swirl=0,travel=0,time=0,linger=.8,fade_in=.12,fade_out=.16,
            blend_arc=0,blend_spread=0,ramp=ramp)
        events.append(a)
        b=dict(a);b.update(t=.4,path=pose_path(after),time=.166,linger=.32)
        events.append(b)
    def span(p,q,lo=.10,hi=.90):
        return [(p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t) for t in [lo,(lo+hi)/2,hi]]
    for j,width in enumerate([34,31,28,25,21]):
        piece('armor_'+str(j),'carapace',span(raised[j],raised[j+1]),span(landed[j],landed[j+1]),width)
    for j in range(1,5):
        p=raised[j];q=landed[j]
        piece('joint_'+str(j),'carapace',[(p[0]-4,p[1]-4),(p[0]+4,p[1]+4)],[(q[0]-4,q[1]-4),(q[0]+4,q[1]+4)],10,3000,['181510','38291e','715035','9a794e','c4a97b'])
    piece('venom_sac','carapace',[(89,-151),(107,-131),(114,-112)],[(-8,101),(6,126),(7,147)],29,16000)
    piece('needle','stinger',[(112,-112),(140,-91),(132,-57),(102,-24),(72,-2)],[(7,145),(15,166),(10,190),(0,220)],16,12000,['251b14','795532','bc9560','e0c99a','f1dfbc'])
    write('scorpion','蝎女 · 五节蝎尾重刺',events,[512,576],[256,300],54)

    impact=[]
    for side in [-1,1]:
        e=stream('ground_sand_'+str(side),[(side*190*(k/11)**.65,-5-18*math.sin(k/11*math.pi)) for k in range(12)])
        e.update(count=6500,width=13,sand_floor=360,sand_dust=.55,sand_grain=.9,stream_edge=20,
                 travel=.10,linger=.12,fade_in=.001,fade_out=.21,stream_flow=0,stream_curl=1.0)
        impact.append(e)
    impact.append(dict(t=0,do='quake',x=640,y=360,unit='earth',form='surge',mode='radial',
        perspective=.15,travel=.045,ease=.8,width=190,strength=1.4,body=False,flash=0,shake=0,
        wave=False,cracks=True,crack_amount=2,crack_time=.35,crack_glow=0,
        debris='stone',unit_size=.6,spacing=20,debris_density=.35,debris_height=42,
        dust=True,dust_color='c9ad79',dust_height=20,dust_spread=45,dust_density=.5,dust_time=.24,ramp=RAMP,seed=411))
    write('slam_impact','蝎女 · 尾刺落地冲砂',impact,[512,256],[256,224],36)

if __name__=='__main__': main()

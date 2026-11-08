"""Articulate the accepted polygon silhouette; preserve all source shape coordinates."""
import json, math, random
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
FOLDER = ROOT/'combat-vfx-studio/studies/sandstorm_scorpion'
source = json.loads((FOLDER/'ghost.json').read_text(encoding='utf-8'))['shapes']
points = [(159,191),(152,162),(137,132),(131,101),(143,70),(167,44),(197,29),(228,29),(253,45)]
parts = []
def part(name, shapes, origin, angle):
    c,s=math.cos(angle),math.sin(angle)
    polygons=[]
    for shape in shapes:
        polygons.append([[(x-origin[0])*c+(y-origin[1])*s, -(x-origin[0])*s+(y-origin[1])*c] for x,y in shape['points']])
    parts.append(dict(name=name,polygons=polygons))

# Explicit shape ranges come from the authoring generator: limbs/claws 0..131,
# eight 7-facet tail plates 132..187, hook 188..192, torso/head 193 onward.
part('body',source[:132]+source[193:],(-60,-40),0)
lengths=[];rest=[]
for i,(a,b) in enumerate(zip(points,points[1:])):
    angle=math.atan2(b[1]-a[1],b[0]-a[0])
    lengths.append(math.dist(a,b));rest.append(math.degrees(angle))
    part('tail_'+str(i),[source[132+i*7]],a,angle)
part('sting',[source[188]],points[-1],-.12)

rng=random.Random(81631)
areas=[];pixels=[]
for p in parts:
    mask=Image.new('L',(600,600));d=ImageDraw.Draw(mask)
    for poly in p['polygons']:d.polygon([(x+100,y+100) for x,y in poly],fill=255)
    filled=[(x-100,y-100) for y in range(600) for x in range(600) if mask.getpixel((x,y))]
    areas.append(len(filled));pixels.append(filled)
for p,filled,area in zip(parts,pixels,areas):
    count=round(6800*area/sum(areas))
    p['grains']=[[x+rng.random()-.5,y+rng.random()-.5,rng.random(),rng.random(),rng.random()]
                 for x,y in rng.choices(filled,k=count)]
wind=[a+b for a,b in zip(rest,[-8,-12,-16,-18,-18,-12,-8,-4])]
doc=dict(root=[219,231],lengths=lengths,rest=rest,wind=wind,
         strike=[-32,-13,8,35,64,83,102,120],hook_rest=-.12,hook_wind=-.30,hook_strike=.06,
         wind_start=1.15,wind_end=1.70,strike_start=1.95,strike_end=2.16,hold_end=2.42,
         parts=parts)
(FOLDER/'tail_rig.json').write_text(json.dumps(doc,separators=(',',':')),encoding='utf-8')
print('Authored fixed-length tail rig: 8 links, 1 hook, fixed body;',sum(len(p['grains']) for p in parts),'grains')

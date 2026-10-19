from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT = ROOT / "motion-blocking-v2.png"
W, H, FOOT = 192, 192, 176

# head, neck, shoulders, chest, pelvis, knees, feet, sword arm, empty arm, sword tip
P = [
((104,56),(103,70),(91,79),(113,80),(102,94),(100,122),(88,146),(111,146),(82,175),(120,175),(91,82),(85,100),(76,113),(113,83),(119,95),(129,92),(39,159)),
((101,70),(100,84),(89,93),(112,92),(100,106),(101,132),(79,151),(126,151),(60,175),(143,175),(89,96),(83,119),(88,139),(112,96),(121,109),(134,104),(143,170)),
((94,89),(96,102),(86,113),(108,111),(99,121),(103,140),(76,151),(130,151),(49,175),(151,175),(87,116),(83,137),(98,151),(108,114),(119,127),(134,118),(156,174)),
((91,84),(94,98),(86,108),(110,107),(101,119),(105,139),(78,151),(130,150),(51,175),(151,175),(87,110),(94,124),(108,119),(110,109),(121,123),(135,117),(157,75)),
((80,73),(87,88),(84,98),(110,101),(99,113),(105,139),(80,151),(130,151),(52,175),(151,175),(86,101),(102,106),(120,82),(110,104),(121,119),(135,115),(166,12)),
((82,69),(89,84),(85,95),(111,98),(100,110),(105,137),(82,151),(129,151),(56,175),(149,175),(87,97),(96,82),(98,64),(111,101),(122,115),(135,117),(125,13)),
((89,66),(94,81),(88,92),(113,94),(102,107),(105,134),(85,150),(126,150),(64,175),(145,175),(89,95),(82,83),(79,68),(113,97),(124,110),(135,111),(70,17)),
((98,62),(99,77),(90,88),(113,89),(101,103),(102,129),(88,148),(118,148),(76,175),(130,175),(91,91),(84,106),(76,121),(113,92),(122,104),(132,101),(40,160)),
((104,56),(103,70),(91,79),(113,80),(102,94),(100,122),(88,146),(111,146),(82,175),(120,175),(91,82),(85,100),(76,113),(113,83),(119,95),(129,92),(39,159)),
]
SRC={0:'1.png',2:'3.png',4:'5.png',8:'8.png'}
LABEL={0:'A / SOURCE 1',2:'B / SOURCE 3',4:'C / SOURCE 5',8:'D / SOURCE 8'}

def volume(d, pts, fill, edge):
    d.polygon(pts,fill=fill)
    d.line(pts+[pts[0]],fill=edge,width=2,joint='curve')

def limb(d,a,b,c,color):
    d.line((a,b,c),fill=color,width=8,joint='curve')
    for x,y in (a,b,c): d.ellipse((x-4,y-4,x+4,y+4),fill=color)

def mannequin(tile,p):
    d=ImageDraw.Draw(tile,'RGBA')
    h,n,sl,sr,ch,pe,kl,kr,fl,fr,sa,se,sh,ea,ee,eh,tip=p
    ink=(30,36,44,235); orange=(224,91,48,255); blue=(55,132,214,255); mass=(168,72,196,255)
    limb(d,pe,kl,fl,ink); limb(d,pe,kr,fr,ink)
    volume(d,[(pe[0]-13,pe[1]-7),(pe[0]+14,pe[1]-6),(pe[0]+12,pe[1]+7),(pe[0]-12,pe[1]+7)],(30,36,44,90),ink)
    volume(d,[sl,sr,(ch[0]+10,ch[1]+13),(ch[0]-10,ch[1]+13)],(30,36,44,72),ink)
    d.line((n,ch,pe),fill=mass,width=3)
    limb(d,sa,se,sh,orange); limb(d,ea,ee,eh,blue)
    d.line((sh,tip),fill=orange,width=5)
    d.ellipse((h[0]-9,h[1]-9,h[0]+9,h[1]+9),fill=(255,255,255,210),outline=ink,width=3)
    d.ellipse((pe[0]-4,pe[1]-4,pe[0]+4,pe[1]+4),fill=mass)
    d.line((fl[0]-7,fl[1],fl[0]+8,fl[1]),fill=ink,width=5)
    d.line((fr[0]-7,fr[1],fr[0]+8,fr[1]),fill=ink,width=5)

def main():
    sheet=Image.new('RGBA',(W*9,H+46),(239,241,244,255)); sd=ImageDraw.Draw(sheet,'RGBA')
    for i,p in enumerate(P):
        tile=Image.new('RGBA',(W,H),(255,255,255,255)); td=ImageDraw.Draw(tile,'RGBA')
        td.line((8,FOOT,184,FOOT),fill=(205,60,55,180),width=1)
        if i in SRC:
            src=Image.open(ROOT/SRC[i]).convert('RGBA')
            src.putalpha(src.getchannel('A').point(lambda a:round(a*.26)))
            tile.alpha_composite(src)
        mannequin(tile,p); sheet.alpha_composite(tile,(i*W,0))
        sd.text((i*W+8,H+8),f"F{i+1:02}  {LABEL.get(i,'IN-BETWEEN')}",fill=(24,28,34,255))
        sd.text((i*W+8,H+25),'LOCKED' if i in SRC else 'ROUGH',fill=(178,52,47,255) if i in SRC else (80,86,96,255))
    sheet.save(OUT)

if __name__=='__main__': main()

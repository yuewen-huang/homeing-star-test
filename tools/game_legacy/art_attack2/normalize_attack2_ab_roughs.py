from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT = ROOT / "ab-silhouette-v1"
INPUTS = [
    (Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-c4d4fcd5-c7b9-4e8f-8314-03f3faf6da5f.png"), 128),
    (Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-803125b8-8bf3-4ba2-9820-5c717f8922c0.png"), 112),
]

def normalize(path, target_h):
    im=Image.open(path).convert('RGBA'); box=im.getbbox(); crop=im.crop(box)
    scale=target_h/crop.height
    crop=crop.resize((round(crop.width*scale),target_h),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',(192,192),(0,0,0,0))
    out.alpha_composite(crop,((192-crop.width)//2,176-crop.height))
    return out

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    roughs=[]
    for i,(path,h) in enumerate(INPUTS,1):
        im=normalize(path,h); im.save(OUT/f'ab-{i}.png'); roughs.append(im)
    frames=[Image.open(ROOT/'1.png').convert('RGBA'),*roughs,Image.open(ROOT/'3.png').convert('RGBA')]
    sheet=Image.new('RGBA',(4*224,232),(238,238,238,255)); d=ImageDraw.Draw(sheet)
    for i,im in enumerate(frames):
        ox=i*224+16; oy=16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255)
                d.rectangle((ox+x,oy+y,ox+x+11,oy+y+11),fill=c)
        sheet.alpha_composite(im,(ox,oy)); d.line((ox,oy+176,ox+191,oy+176),fill=(210,62,58,255),width=1)
        d.text((ox,212),['A LOCKED','AB ROUGH 1','AB ROUGH 2','B LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

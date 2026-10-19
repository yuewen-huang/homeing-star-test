from collections import deque
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT=ROOT/'ab-final-v1'
F1=Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-05262896-e5cd-4078-b344-18ff1aae6cd3.png")
F2=Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-e5c1df29-cfeb-493e-95f3-06238c1b4e49.png")

def remove_checker(im):
    rgb=im.convert('RGB'); w,h=rgb.size; px=rgb.load()
    bg=bytearray(w*h); q=deque()
    def eligible(x,y):
        r,g,b=px[x,y]
        # Generated checkerboards contain several gray values and warped antialiasing.
        return max(r,g,b)-min(r,g,b)<24 and max(r,g,b)>70
    def add(x,y):
        k=y*w+x
        if not bg[k] and eligible(x,y): bg[k]=1; q.append((x,y))
    for x in range(w): add(x,0); add(x,h-1)
    for y in range(h): add(0,y); add(w-1,y)
    while q:
        x,y=q.popleft()
        for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1),(x-1,y-1),(x+1,y-1),(x-1,y+1),(x+1,y+1)):
            if 0<=nx<w and 0<=ny<h: add(nx,ny)
    a=Image.new('L',(w,h),255); ap=a.load()
    for y in range(h):
        for x in range(w):
            if bg[y*w+x]: ap[x,y]=0
    a=a.filter(ImageFilter.GaussianBlur(.45)); out=rgb.convert('RGBA'); out.putalpha(a); return out

def normalize(im,target_h):
    # Ignore isolated near-transparent generation noise when resolving the sprite bounds.
    box=im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
    crop=im.crop(box); s=target_h/crop.height
    crop=crop.resize((round(crop.width*s),target_h),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',(192,192),(0,0,0,0)); out.alpha_composite(crop,((192-crop.width)//2,176-target_h)); return out

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    raw_one=Image.open(F1)
    one_needs_cut = raw_one.mode!='RGBA' or raw_one.getchannel('A').getextrema()==(255,255)
    one=normalize(remove_checker(raw_one) if one_needs_cut else raw_one.convert('RGBA'),128)
    raw_two=Image.open(F2)
    two_needs_cut = raw_two.mode!='RGBA' or raw_two.getchannel('A').getextrema()==(255,255)
    two=normalize(remove_checker(raw_two) if two_needs_cut else raw_two.convert('RGBA'),120)
    one.save(OUT/'2.png'); two.save(OUT/'3.png')
    seq=[Image.open(ROOT/'1.png').convert('RGBA'),one,two,Image.open(ROOT/'3.png').convert('RGBA')]
    sheet=Image.new('RGBA',(896,232),(238,238,238,255)); d=ImageDraw.Draw(sheet)
    for i,frame in enumerate(seq):
        ox=i*224+16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255); d.rectangle((ox+x,16+y,ox+x+11,27+y),fill=c)
        sheet.alpha_composite(frame,(ox,16)); d.line((ox,192,ox+191,192),fill=(210,62,58,255),width=1)
        d.text((ox,212),['A / LOCKED','AB / FINAL 1','AB / FINAL 2','B / LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

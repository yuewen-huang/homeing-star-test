from collections import deque
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT=ROOT/'ab-single-final-v4-template'
SOURCE=Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-f4dfa11b-2910-466f-9cb9-ab131a4ef52a.png")

def cut_checker(im):
    rgb=im.convert('RGB'); w,h=rgb.size; px=rgb.load(); bg=bytearray(w*h); q=deque()
    def add(x,y):
        k=y*w+x
        if bg[k]: return
        r,g,b=px[x,y]
        if max(r,g,b)-min(r,g,b)<24 and max(r,g,b)>70: bg[k]=1; q.append((x,y))
    for x in range(w): add(x,0); add(x,h-1)
    for y in range(h): add(0,y); add(w-1,y)
    while q:
        x,y=q.popleft()
        for dx,dy in ((-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)):
            nx,ny=x+dx,y+dy
            if 0<=nx<w and 0<=ny<h: add(nx,ny)
    a=Image.new('L',(w,h),255); ap=a.load()
    for y in range(h):
        for x in range(w):
            if bg[y*w+x]: ap[x,y]=0
    out=rgb.convert('RGBA'); out.putalpha(a); return out

def normalize(im):
    box=im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox(); crop=im.crop(box)
    target_h=128; s=target_h/crop.height
    crop=crop.resize((round(crop.width*s),target_h),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',(192,192),(0,0,0,0)); out.alpha_composite(crop,((192-crop.width)//2,176-target_h)); return out

def quantize(im):
    refs=[Image.open(ROOT/'1.png').convert('RGBA'),Image.open(ROOT/'3.png').convert('RGBA'),im]
    samples=[]
    for src in refs: samples.extend((r,g,b) for r,g,b,a in src.getdata() if a>=128)
    step=max(1,len(samples)//4096); strip=Image.new('RGB',(len(samples[::step]),1)); strip.putdata(samples[::step])
    pal=strip.quantize(colors=48,method=Image.Quantize.MEDIANCUT)
    alpha=im.getchannel('A').point(lambda a:255 if a>=64 else 0)
    out=im.convert('RGB').quantize(palette=pal,dither=Image.Dither.NONE).convert('RGBA'); out.putalpha(alpha); return out

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    raw=Image.open(SOURCE); rgba=cut_checker(raw) if raw.mode!='RGBA' or raw.getchannel('A').getextrema()==(255,255) else raw.convert('RGBA')
    frame=quantize(normalize(rgba)); frame.save(OUT/'2.png')
    seq=[Image.open(ROOT/'1.png').convert('RGBA'),frame,Image.open(ROOT/'3.png').convert('RGBA')]
    sheet=Image.new('RGBA',(672,232),(238,238,238,255)); d=ImageDraw.Draw(sheet)
    for i,sprite in enumerate(seq):
        ox=i*224+16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255); d.rectangle((ox+x,16+y,ox+x+11,27+y),fill=c)
        sheet.alpha_composite(sprite,(ox,16)); d.line((ox,192,ox+191,192),fill=(210,62,58,255),width=1)
        d.text((ox,212),['A LOCKED','ONLY IN-BETWEEN','B LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

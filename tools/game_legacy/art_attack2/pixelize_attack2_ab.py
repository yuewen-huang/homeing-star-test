import colorsys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
SRC=ROOT/'ab-final-v1'; OUT=ROOT/'ab-final-pixel-v1'

def fur_fix(im):
    im=im.copy().convert('RGBA'); px=im.load()
    # Head/ear region only. Keep white muzzle and black outline untouched.
    for y in range(45,106):
        for x in range(48,122):
            r,g,b,a=px[x,y]
            h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
            if a>=32 and .025<h<.145 and s>.24 and .14<v<.82:
                h=h*.45+.078*.55; s=s*.62; v=v*.92
                nr,ng,nb=colorsys.hsv_to_rgb(h,s,v)
                px[x,y]=(round(nr*255),round(ng*255),round(nb*255),a)
    return im

def shared_palette(images, colors=48):
    samples=[]
    for im in images:
        samples.extend((r,g,b) for r,g,b,a in im.convert('RGBA').getdata() if a>=128)
    sw=max(1,min(4096,len(samples))); step=max(1,len(samples)//sw)
    strip=Image.new('RGB',(sw,1)); strip.putdata(samples[::step][:sw])
    return strip.quantize(colors=colors,method=Image.Quantize.MEDIANCUT)

def apply_palette(im,pal):
    rgba=im.convert('RGBA'); a=rgba.getchannel('A').point(lambda v:255 if v>=64 else 0)
    q=rgba.convert('RGB').quantize(palette=pal,dither=Image.Dither.NONE).convert('RGBA'); q.putalpha(a); return q

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    f2=Image.open(SRC/'2.png').convert('RGBA'); f3=fur_fix(Image.open(SRC/'3.png'))
    anchors=[Image.open(ROOT/'1.png').convert('RGBA'),Image.open(ROOT/'3.png').convert('RGBA')]
    pal=shared_palette([*anchors,f2,f3],48)
    p2=apply_palette(f2,pal); p3=apply_palette(f3,pal)
    p2.save(OUT/'2.png'); p3.save(OUT/'3.png')
    seq=[anchors[0],p2,p3,anchors[1]]
    sheet=Image.new('RGBA',(896,232),(238,238,238,255)); d=ImageDraw.Draw(sheet)
    for i,frame in enumerate(seq):
        ox=i*224+16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255); d.rectangle((ox+x,16+y,ox+x+11,27+y),fill=c)
        sheet.alpha_composite(frame,(ox,16)); d.line((ox,192,ox+191,192),fill=(210,62,58,255),width=1)
        d.text((ox,212),['A LOCKED','FINAL 1 / 48C','FINAL 2 / 48C','B LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

from pathlib import Path
from PIL import Image, ImageDraw
from finalize_attack2_ab_single import cut_checker, normalize, quantize

ROOT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT=ROOT/'ab-single-final-v3'
WIDE_SOURCE=Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-0c307dfc-845b-4dc1-bedb-ebb8b6278f31.png")
SERIOUS_HEAD=ROOT/'ab-single-final-v2'/'2.png'

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    raw=Image.open(WIDE_SOURCE)
    rgba=cut_checker(raw) if raw.mode!='RGBA' or raw.getchannel('A').getextrema()==(255,255) else raw.convert('RGBA')
    wide=quantize(normalize(rgba))
    serious=Image.open(SERIOUS_HEAD).convert('RGBA')

    # Head-only featherless pixel mask. It ends above the shoulder line; everything
    # outside it remains byte-for-byte from the approved wide-shoulder base.
    mask=Image.new('L',(192,192),0); d=ImageDraw.Draw(mask)
    d.ellipse((65,39,121,87),fill=255)
    mask=Image.composite(serious.getchannel('A'),Image.new('L',(192,192),0),mask)
    out=wide.copy(); out.paste(serious,(0,0),mask); out.save(OUT/'2.png')

    seq=[Image.open(ROOT/'1.png').convert('RGBA'),out,Image.open(ROOT/'3.png').convert('RGBA')]
    sheet=Image.new('RGBA',(672,232),(238,238,238,255)); sd=ImageDraw.Draw(sheet)
    for i,sprite in enumerate(seq):
        ox=i*224+16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255); sd.rectangle((ox+x,16+y,ox+x+11,27+y),fill=c)
        sheet.alpha_composite(sprite,(ox,16)); sd.line((ox,192,ox+191,192),fill=(210,62,58,255),width=1)
        sd.text((ox,212),['A LOCKED','WIDE BODY + HEAD MASK','B LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

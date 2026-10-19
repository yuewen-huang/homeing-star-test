from pathlib import Path
from PIL import Image, ImageDraw
from finalize_attack2_ab_single import cut_checker

ROOT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1")
OUT=ROOT/'bc-silhouette-v1'
ITEMS=[
 (Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-ad342f7c-46a3-479a-9468-5508009f092b.png"),102,101.5),
 (Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-e1748ac4-4630-458d-b82b-02328b2d9874.png"),149,111),
 (Path(r"D:\CodexData\.codex\generated_images\01a090e6-aed5-76e2-8790-adfe0fa3b709\exec-dda48165-861a-4837-b9db-b3d26e9fdb66.png"),166,96.5),
]

def normalize(path,target_h,cx):
    raw=Image.open(path); needs=raw.mode!='RGBA' or raw.getchannel('A').getextrema()==(255,255)
    im=cut_checker(raw) if needs else raw.convert('RGBA')
    box=im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox(); crop=im.crop(box); s=target_h/crop.height
    crop=crop.resize((round(crop.width*s),target_h),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',(192,192),(0,0,0,0)); out.alpha_composite(crop,(round(cx-crop.width/2),176-target_h)); return out

def restore_guide_sword(im,index):
    # Gray blades can be mistaken for checkerboard during extraction; restore them
    # directly from the user's blue guide axes for the blocking preview.
    if index==1: grip,tip=(86,134),(162,159)
    elif index==2: grip,tip=(105,78),(175,28)
    elif index==3: grip,tip=(105,67),(102,11)
    else: return
    d=ImageDraw.Draw(im,'RGBA'); d.line((grip,tip),fill=(166,172,178,255),width=7)
    gx,gy=grip; d.line((gx-6,gy-6,gx+6,gy+6),fill=(151,105,49,255),width=5)

def make_bald_block(im,index):
    specs={
      1:((73,68,116,106),(86,73,108,97)),
      2:((61,42,106,84),(75,48,96,72)),
      3:((83,45,124,89),(94,52,115,77)),
    }
    clear_box,head_box=specs[index]; px=im.load()
    cap_clear={1:(73,68,117,100),2:(61,40,110,70),3:(84,43,124,72)}[index]
    for y in range(cap_clear[1],cap_clear[3]):
        for x in range(cap_clear[0],cap_clear[2]): px[x,y]=(0,0,0,0)
    # Remove only brown hair pixels inside the head zone; arms and coat stay untouched.
    for y in range(clear_box[1],clear_box[3]):
        for x in range(clear_box[0],clear_box[2]):
            r,g,b,a=px[x,y]
            if a and r>g and g>=b and r<155 and b<105: px[x,y]=(0,0,0,0)
    # Remove remaining dark hair lobes outside the mannequin cranium.
    extra={1:[(104,68,117,93)],2:[(61,42,90,63)],3:[(84,45,94,68)]}
    for x0,y0,x1,y1 in extra[index]:
        for y in range(y0,y1):
            for x in range(x0,x1): px[x,y]=(0,0,0,0)
    d=ImageDraw.Draw(im,'RGBA')
    # Flat mannequin head: no hair, ears, face, or costume detail.
    d.ellipse(head_box,fill=(220,184,151,255),outline=(74,60,52,255),width=2)

def main():
    OUT.mkdir(parents=True,exist_ok=True); rough=[]
    for i,item in enumerate(ITEMS,1):
        im=normalize(*item); restore_guide_sword(im,i); im.save(OUT/f'bc-{i}.png'); rough.append(im)
    seq=[Image.open(ROOT/'3.png').convert('RGBA'),*rough,Image.open(ROOT/'5.png').convert('RGBA')]
    sheet=Image.new('RGBA',(1120,232),(238,238,238,255)); d=ImageDraw.Draw(sheet)
    for i,sprite in enumerate(seq):
        ox=i*224+16
        for y in range(0,192,12):
            for x in range(0,192,12):
                c=(216,216,216,255) if (x//12+y//12)%2 else (245,245,245,255); d.rectangle((ox+x,16+y,ox+x+11,27+y),fill=c)
        sheet.alpha_composite(sprite,(ox,16)); d.line((ox,192,ox+191,192),fill=(210,62,58,255),width=1)
        d.text((ox,212),['B LOCKED','BC ROUGH 1','BC ROUGH 2','BC ROUGH 3','C LOCKED'][i],fill=(24,24,24,255))
    sheet.save(OUT/'preview.png')

if __name__=='__main__': main()

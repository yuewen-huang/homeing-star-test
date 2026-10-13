from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(r"D:\homing-star-godot\PendingArt\character\师傅\参考\Elementals_fire_knight_FREE_v1.1\png\fire_knight\05_1_atk")
OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\视频抽帧版本\攻击1\骨架-参考逐帧描摹")
W, H = 288, 128

# Coordinates are traced in the native 288x128 reference-frame coordinate system.
# h,ch,pe, ls,le,lh, rs,re,rh, lhip,lk,la, rhip,rk,ra, grip, sword_tip
P = [
 ((143,91),(140,102),(139,112),(134,99),(132,104),(136,106),(146,100),(144,105),(139,107),(135,112),(128,118),(126,126),(143,112),(149,118),(152,126),(138,106),(109,124)),
 ((139,88),(135,100),(135,109),(129,97),(124,103),(129,106),(141,98),(139,104),(134,106),(130,109),(124,117),(120,125),(140,109),(151,114),(148,125),(132,106),(111,124)),
 ((143,84),(139,96),(139,108),(133,93),(130,88),(133,86),(145,94),(140,89),(136,87),(133,109),(128,117),(126,126),(145,109),(153,115),(151,126),(134,87),(120,126)),
 ((153,72),(149,88),(148,104),(141,85),(145,78),(151,75),(156,86),(157,79),(154,75),(143,106),(136,115),(127,125),(153,106),(160,111),(157,124),(153,75),(119,82)),
 ((153,91),(149,102),(148,110),(143,99),(149,101),(155,103),(156,99),(158,102),(156,104),(143,111),(136,117),(130,126),(153,111),(159,116),(156,126),(156,103),(211,125)),
 ((154,91),(150,102),(149,110),(144,99),(150,102),(156,104),(157,99),(160,103),(158,105),(144,111),(136,118),(130,126),(154,111),(160,117),(157,126),(158,104),(210,125)),
 ((154,92),(150,103),(149,111),(144,100),(150,103),(156,105),(157,100),(160,104),(158,106),(144,112),(136,118),(130,126),(154,112),(159,118),(157,126),(158,105),(209,125)),
 ((154,93),(150,104),(149,112),(144,101),(150,104),(156,106),(157,101),(160,105),(158,107),(144,112),(136,119),(130,126),(154,112),(159,119),(157,126),(158,106),(207,124)),
 ((146,89),(142,101),(145,112),(136,98),(140,104),(148,106),(149,99),(153,104),(150,107),(141,112),(134,119),(132,126),(149,112),(157,119),(163,126),(150,106),(186,118)),
 ((143,88),(140,100),(141,111),(134,97),(137,102),(142,103),(146,98),(148,102),(144,104),(137,111),(130,118),(128,126),(145,111),(152,118),(156,126),(143,103),(127,124)),
 ((143,89),(140,101),(139,112),(134,98),(133,104),(137,106),(146,99),(144,105),(139,107),(135,112),(128,118),(126,126),(143,112),(149,118),(152,126),(138,106),(100,124)),
]

ARCS = {
 5: [(118,72),(132,56),(153,47),(177,47),(197,58),(209,78),(211,103),(211,125)],
 6: [(171,47),(191,58),(205,77),(210,100),(210,125)],
 7: [(185,55),(199,75),(208,97),(209,125)],
 8: [(207,92),(207,108),(207,124)],
}

def line(d, points, fill, width=2): d.line(points, fill=fill, width=width, joint="curve")
def dot(d, p, fill, r=2): d.ellipse((p[0]-r,p[1]-r,p[0]+r,p[1]+r), fill=fill)

def draw_skeleton(base: Image.Image, pose, idx: int, overlay=False):
    d=ImageDraw.Draw(base)
    h,ch,pe,ls,le,lh,rs,re,rh,lhip,lk,la,rhip,rk,ra,grip,tip=pose
    if idx in ARCS:
        line(d, ARCS[idx], (255,174,65,180 if overlay else 255), 1)
    line(d,(tip,grip),(25,190,245,220 if overlay else 255),2)
    line(d,(h,ch,pe),(255,235,60,230 if overlay else 255),2)
    line(d,(ls,rs),(255,235,60,230 if overlay else 255),1)
    line(d,(lhip,rhip),(255,235,60,230 if overlay else 255),1)
    line(d,(ls,le,lh),(255,70,70,230 if overlay else 255),2)
    line(d,(rs,re,rh),(70,210,255,230 if overlay else 255),2)
    line(d,(lhip,lk,la),(255,70,70,230 if overlay else 255),2)
    line(d,(rhip,rk,ra),(70,210,255,230 if overlay else 255),2)
    d.ellipse((h[0]-4,h[1]-4,h[0]+4,h[1]+4),outline=(255,235,60,255),width=1)
    line(d,(h,(h[0]+6,h[1]+1)),(255,235,60,255),1)
    for pt in (ch,pe,ls,le,rs,re,lhip,lk,la,rhip,rk,ra): dot(d,pt,(255,235,60,255),1)
    dot(d,lh,(255,70,70,255),2); dot(d,rh,(70,210,255,255),2); dot(d,grip,(255,190,40,255),1)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    clean=[]; overlays=[]
    for idx,pose in enumerate(P,1):
        sk=Image.new("RGBA",(W,H),(14,17,21,255)); draw_skeleton(sk,pose,idx)
        src=Image.open(SRC/f"1_atk_{idx}.png").convert("RGBA")
        ov=Image.new("RGBA",(W,H),(14,17,21,255)); ov.alpha_composite(src); draw_skeleton(ov,pose,idx,True)
        sk.save(OUT/f"attack1-traced-skeleton-{idx:02d}.png")
        ov.save(OUT/f"attack1-trace-check-{idx:02d}.png")
        clean.append(sk); overlays.append(ov)
    for name, frames in (("attack1-traced-skeleton-preview.png",clean),("attack1-trace-check-preview.png",overlays)):
        sheet=Image.new("RGBA",(W*4,H*3),(14,17,21,255))
        for n,f in enumerate(frames): sheet.alpha_composite(f,((n%4)*W,(n//4)*H))
        sheet.save(OUT/name)
    leg_check=Image.new("RGBA",(128*8,7*56*8),(14,17,21,255))
    for row, ov in enumerate(overlays[1:8]):
        crop=ov.crop((96,72,224,128)).resize((128*8,56*8),Image.Resampling.NEAREST)
        leg_check.alpha_composite(crop,(0,row*56*8))
    leg_check.save(OUT/"attack1-legs-02-08-trace-check-8x.png")
    # Preserve the source GIF timing exactly: 11 frames at 100 ms each.
    durations=[100] * 11
    for name, frames in (("attack1-traced-skeleton.gif",clean),("attack1-trace-check.gif",overlays)):
        frames[0].save(OUT/name,save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2)
    print(f"traced_frames={len(P)} native_size={W}x{H} total_ms={sum(durations)}")
    print(OUT)

if __name__ == "__main__": main()

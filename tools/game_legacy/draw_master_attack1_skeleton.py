from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


OUT = Path(r"D:\homing-star-godot\PendingArt\character\师傅\视频抽帧版本\攻击1\骨架")
W, H, FLOOR = 320, 192, 176

# Joints are deliberately authored for the master's broad silhouette, not traced
# as the much smaller Fire Knight body. L/R are the character's anatomical sides.
POSES = [
    # head, chest, pelvis, L shoulder/elbow/hand, R shoulder/elbow/hand,
    # L hip/knee/ankle, R hip/knee/ankle, sword grip/tip
    ((181, 38),(171, 78),(164,116),(151,70),(147,94),(157,109),(190,73),(181,96),(165,107),(153,117),(139,146),(126,176),(176,117),(197,145),(220,176),(161,108),(39,169)),
    ((171, 52),(160, 88),(155,125),(141,82),(137,104),(147,116),(179,84),(169,105),(154,114),(145,126),(130,150),(119,176),(166,126),(184,150),(205,176),(150,115),(60,171)),
    ((157, 58),(147, 91),(151,127),(130,86),(126,108),(136,116),(165,88),(156,107),(143,115),(140,128),(128,151),(116,176),(163,128),(180,150),(200,176),(139,115),(111,174)),
    # Launch: both boots clearly leave the baseline while the sword is carried overhead.
    ((169, 39),(164, 72),(160,104),(146,68),(150,51),(159,45),(182,69),(176,53),(166,47),(150,105),(137,129),(128,154),(172,105),(188,130),(204,159),(162,46),(89,22)),
    # Apex: compressed airborne silhouette, sword moved behind/right for the chop.
    ((176, 34),(171, 67),(168,101),(153,63),(160,49),(171,43),(189,65),(188,49),(179,42),(158,102),(145,126),(138,151),(180,102),(194,127),(207,155),(175,42),(257,27)),
    # Descent: torso and pelvis drive down; hands accelerate the blade toward the floor.
    ((184, 48),(179, 82),(174,116),(160,78),(173,88),(190,99),(197,81),(202,94),(195,103),(164,117),(151,141),(144,167),(186,117),(202,141),(216,169),(193,101),(276,172)),
    # Impact: wide crouched landing, both feet planted, sword tip at the strike point.
    ((181, 63),(175, 97),(169,132),(155,93),(169,106),(190,118),(193,96),(199,110),(194,121),(157,133),(141,153),(128,176),(181,133),(202,153),(222,176),(192,119),(278,176)),
    # Follow-through: remain low for one frame so the landing has weight.
    ((176, 67),(169,101),(166,134),(151,97),(160,113),(178,124),(187,99),(190,115),(181,126),(154,135),(139,155),(128,176),(178,135),(198,155),(220,176),(179,125),(268,153)),
    ((158, 56),(151, 91),(156,128),(134,86),(140,104),(154,113),(168,90),(174,105),(162,116),(145,129),(130,150),(119,176),(168,129),(187,150),(208,176),(159,115),(256,158)),
    ((168, 48),(162, 84),(162,123),(145,79),(151,94),(160,101),(180,80),(173,95),(164,102),(151,124),(137,149),(126,176),(175,124),(193,149),(214,176),(162,102),(101,55)),
    ((181, 38),(171, 78),(164,116),(151,70),(147,94),(157,109),(190,73),(181,96),(165,107),(153,117),(139,146),(126,176),(176,117),(197,145),(220,176),(161,108),(39,169)),
]


def line(draw, pts, color, width=3):
    draw.line(pts, fill=color, width=width, joint="curve")


def dot(draw, p, color, r=3):
    x, y = p
    draw.ellipse((x-r, y-r, x+r, y+r), fill=color, outline=(18,18,20,255))


def render(index: int, pose) -> Image.Image:
    im = Image.new("RGBA", (W, H), (15, 18, 22, 255))
    d = ImageDraw.Draw(im)
    d.line((0, FLOOR, W, FLOOR), fill=(82, 92, 102, 255), width=1)
    d.line((160, 0, 160, H), fill=(35, 42, 49, 255), width=1)

    (head,chest,pelvis,ls,le,lh,rs,re,rh,lhip,lk,la,rhip,rk,ra,grip,tip) = pose
    # Sword first so hands remain readable. The short perpendicular bar is guard.
    line(d, (tip, grip), (34, 178, 238, 255), 4)
    gx, gy = grip; tx, ty = tip
    dx, dy = gx-tx, gy-ty
    mag = max(1.0, (dx*dx+dy*dy)**0.5)
    nx, ny = -dy/mag*8, dx/mag*8
    line(d, ((gx-nx, gy-ny), (gx+nx, gy+ny)), (255, 196, 54, 255), 3)
    dot(d, tip, (34, 178, 238, 255), 2)

    line(d, (head, chest, pelvis), (244, 226, 78, 255), 4)
    line(d, (ls, rs), (244, 226, 78, 255), 3)
    line(d, (lhip, rhip), (244, 226, 78, 255), 3)
    line(d, (ls, le, lh), (255, 94, 84, 255), 4)
    line(d, (rs, re, rh), (95, 210, 255, 255), 4)
    line(d, (lhip, lk, la), (255, 94, 84, 255), 4)
    line(d, (rhip, rk, ra), (95, 210, 255, 255), 4)
    line(d, ((la[0]-7,FLOOR),(la[0]+6,FLOOR)), (255,94,84,255), 4)
    line(d, ((ra[0]-6,FLOOR),(ra[0]+8,FLOOR)), (95,210,255,255), 4)

    d.ellipse((head[0]-9,head[1]-10,head[0]+9,head[1]+10), outline=(244,226,78,255), width=3)
    # Facing marker / muzzle axis.
    line(d, (head, (head[0]+13, head[1]+2)), (244,226,78,255), 2)
    for p in (chest,pelvis,ls,le,rs,re,lhip,lk,la,rhip,rk,ra):
        dot(d, p, (244,226,78,255), 3)
    # The two hands are intentionally separate even when the grip overlaps.
    dot(d, lh, (255,94,84,255), 4)
    dot(d, rh, (95,210,255,255), 4)
    dot(d, grip, (255,196,54,255), 2)

    d.text((6, 5), f"ATK1 {index:02d}", fill=(238,238,238,255))
    d.text((6, 18), "L red / R cyan", fill=(170,180,190,255))
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []
    for i, pose in enumerate(POSES, 1):
        frame = render(i, pose)
        frame.save(OUT / f"attack1-skeleton-{i:02d}.png")
        frames.append(frame)

    strip = Image.new("RGBA", (W*len(frames), H), (0,0,0,0))
    for i, frame in enumerate(frames):
        strip.alpha_composite(frame, (i*W, 0))
    strip.save(OUT / "attack1-skeleton-strip.png")

    thumb = (W//2, H//2)
    preview = Image.new("RGBA", (thumb[0]*4, thumb[1]*3), (28,31,36,255))
    for i, frame in enumerate(frames):
        small = frame.resize(thumb, Image.Resampling.NEAREST)
        preview.alpha_composite(small, ((i%4)*thumb[0], (i//4)*thumb[1]))
    preview.save(OUT / "attack1-skeleton-preview.png")

    durations = [140, 160, 150, 70, 65, 55, 80, 100, 120, 130, 140]
    frames[0].save(OUT / "attack1-skeleton-preview.gif", save_all=True,
                   append_images=frames[1:], duration=durations, loop=0, disposal=2)
    print(f"frames={len(frames)} size={W}x{H} floor={FLOOR}")
    print(f"durations_ms={durations} total_ms={sum(durations)}")
    print(OUT)


if __name__ == "__main__":
    main()

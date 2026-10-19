from pathlib import Path
from PIL import Image

SRC=Path(r"D:\Temp\codex-clipboard-d67f6091-4e9c-400c-8cfd-06112ac43aa4.png")
OUT=Path(r"D:\homing-star-godot\PendingArt\character\师傅\BOSS形态\采用\攻击\2\概念帧\normalized-v1\user-skeletons")

def main():
    im=Image.open(SRC).convert('RGBA'); OUT.mkdir(parents=True,exist_ok=True)
    panels={
        'bc-inbetween-1.png':(397,7,772,388),
        'bc-inbetween-2.png':(777,7,1148,388),
        'bc-inbetween-3.png':(1153,7,1546,388),
    }
    for name,box in panels.items():
        im.crop(box).resize((192,192),Image.Resampling.LANCZOS).save(OUT/name)

if __name__=='__main__': main()

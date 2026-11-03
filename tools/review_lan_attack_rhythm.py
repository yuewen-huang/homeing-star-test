"""Same-input first-chain excerpt from the native before/after recordings."""
from pathlib import Path
import io
from PIL import Image, ImageDraw
from review_lan_control import frames

out=Path(__file__).resolve().parents[1]/'artifacts/lan_attack_rhythm_20261104'
indexes={n:frames(out/f'{n}.avi') for n in ['before','after']}
images=[]
for frame in range(60,106,2):
    canvas=Image.new('RGB',(960,260),(20,30,38))
    draw=ImageDraw.Draw(canvas)
    for side,name in enumerate(['before','after']):
        offset,size=indexes[name][frame]
        with (out/f'{name}.avi').open('rb') as f:
            f.seek(offset)
            im=Image.open(io.BytesIO(f.read(size))).crop((360,310,1000,610))
            im.thumbnail((480,225))
            canvas.paste(im,(side*480,30))
            draw.text((side*480+12,8),f'{name.upper()} - frame {frame}',fill='white')
    images.append(canvas)
images[0].save(out/'first_chain.gif',save_all=True,append_images=images[1:],duration=[33,34,33]*7+[33,34],loop=0)
sheet=Image.new('RGB',(960,260*6))
for row,index in enumerate([0,5,10,14,18,22]): sheet.paste(images[index],(0,row*260))
sheet.save(out/'first_chain_frames.jpg')

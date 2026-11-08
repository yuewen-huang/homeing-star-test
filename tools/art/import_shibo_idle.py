from pathlib import Path
from PIL import Image
import json
root=Path('D:/HomingStar')
source=root/'homeing-star-temp-assert/ProductionArt/chapter_2_salt/shibo/semi_chibi'
game=root/'homeing-star-game'
im=Image.open(source/'source.png').convert('RGBA')
w,h=im.size[0]//2,im.size[1]//2
frames=[]
for y in range(2):
    for x in range(2):
        frame=im.crop((x*w,y*h,(x+1)*w,(y+1)*h))
        bbox=frame.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        frames.append(frame.crop(bbox))
ratio=96/max(f.height for f in frames)
sheet=Image.new('RGBA',(384,112))
packed=[]
for i,f in enumerate(frames):
    f=f.resize((round(f.width*ratio),round(f.height*ratio)),Image.Resampling.NEAREST)
    cell=Image.new('RGBA',(96,112))
    cell.paste(f,((96-f.width)//2,112-f.height))
    sheet.paste(cell,(i*96,0))
    packed.append(cell)
sheet.save(game/'assets/characters/shibo/body/idle_96x112_4f.png')
# Matching head-and-shoulders portrait, uniformly fitted to the established canvas.
p=frames[0].crop((0,0,frames[0].width,round(frames[0].height*.48)))
p=p.crop(p.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox())
p.thumbnail((120,107),Image.Resampling.NEAREST)
out=Image.new('RGBA',(120,107));out.paste(p,((120-p.width)//2,107-p.height))
out.save(game/'assets/shared/ui/portraits/dialogue_fit/shibo/normal.png')
# Large nearest-neighbor animation preview; game uses the same four frames and timing.
preview=[f.resize((288,336),Image.Resampling.NEAREST) for f in packed]
preview[0].save(source/'idle_preview.gif',save_all=True,append_images=preview[1:],duration=[1650,550,120,180],loop=0,disposal=2)
(source/'packing.json').write_text(json.dumps({'source_size':im.size,'uniform_scale':ratio,'frame_size':[96,112],'feet_y':112,'durations':[1.65,.55,.12,.18]},indent=2))
print(im.size,ratio,[f.size for f in frames])

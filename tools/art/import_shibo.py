from PIL import Image
from pathlib import Path
root=Path('D:/HomingStar/homeing-star-game')
im=Image.open('D:/HomingStar/homeing-star-temp-assert/ProductionArt/chapter_2_salt/shibo/clean.png')
for box,path,size,canvas in [((0,0,400,1024),'assets/characters/shibo/body/idle.png',(100,105),None),((400,0,900,1024),'assets/shared/ui/portraits/dialogue_fit/shibo/normal.png',(120,107),(120,107)),((900,0,1536,1024),'assets/levels/chapter_2_salt/environment/shibo_shelter.png',(240,190),None)]:
    crop=im.crop(box)
    crop=crop.crop(crop.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox())
    crop.thumbnail(size,Image.Resampling.NEAREST)
    if canvas:
        out=Image.new('RGBA',canvas)
        out.paste(crop,((canvas[0]-crop.width)//2,canvas[1]-crop.height))
    else: out=crop
    target=root/path; target.parent.mkdir(parents=True,exist_ok=True); out.save(target)
    print(path, out.size)

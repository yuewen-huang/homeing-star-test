from pathlib import Path
from PIL import Image
root=Path('D:/HomingStar'); source=root/'homeing-star-temp-assert/ProductionArt/chapter_2_salt/story_followup';game=root/'homeing-star-game'
def trim(im):
    return im.crop(im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox())
def save(im,path):
    path=game/path;path.parent.mkdir(parents=True,exist_ok=True);im.save(path)
im=Image.open(source/'apu_source.png').convert('RGBA');w,h=im.width//2,im.height//2
frames=[trim(im.crop((x*w,y*h,(x+1)*w,(y+1)*h))) for y in range(2) for x in range(2)]
ratio=96/max(f.height for f in frames); sheet=Image.new('RGBA',(384,112));cells=[]
for i,f in enumerate(frames):
    f=f.resize((round(f.width*ratio),round(f.height*ratio)),Image.Resampling.NEAREST)
    cell=Image.new('RGBA',(96,112));cell.paste(f,((96-f.width)//2,112-f.height));sheet.paste(cell,(i*96,0));cells.append(cell)
save(sheet,'assets/characters/apu/body/idle_96x112_4f.png')
p=trim(frames[0].crop((0,0,frames[0].width,round(frames[0].height*.46))));p.thumbnail((120,107),Image.Resampling.NEAREST)
out=Image.new('RGBA',(120,107));out.paste(p,((120-p.width)//2,107-p.height));save(out,'assets/shared/ui/portraits/dialogue_fit/apu/normal.png')
previews=[f.resize((288,336),Image.Resampling.NEAREST) for f in cells];previews[0].save(source/'apu_idle.gif',save_all=True,append_images=previews[1:],duration=[1800,500,120,180],loop=0,disposal=2)
im=Image.open(source/'props_source.png').convert('RGBA');print('props',im.size)
# The artwork has a clear gutter below the taller first row, at 56% of its height.
x=im.width//2;y=round(im.height*.56)
for name,box,size in [('rake',(0,0,x,y),(260,190)),('cart',(x,0,im.width,y),(210,140)),('knot',(0,y,x,im.height),(150,90)),('claw_marks',(x,y,im.width,im.height),(180,110))]:
    prop=trim(im.crop(box));prop.thumbnail(size,Image.Resampling.NEAREST);save(prop,'assets/levels/chapter_2_salt/environment/story/'+name+'.png');print(name,prop.size)

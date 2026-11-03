"""Extract MJPEG AVI frames without external video dependencies."""
from pathlib import Path
import io, mmap, struct, json
from PIL import Image, ImageDraw

OUT=Path(__file__).resolve().parents[1]/'artifacts/lan_control_20261104'
def frames(path):
    found=[]
    with path.open('rb') as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as data:
        pos=0
        while True:
            pos=data.find(b'00db',pos)
            if pos<0: break
            size=struct.unpack_from('<I',data,pos+4)[0]
            if data[pos+8:pos+10]==b'\xff\xd8' and size<20000000:
                found.append((pos+8,size))
                pos+=8+size+(size%2)
            else: pos+=4
    return found

def sheet(path, indices, dest, crop=False):
    entries=frames(path)
    canvas=Image.new('RGB',(1280,4*205),(20,30,38))
    draw=ImageDraw.Draw(canvas)
    with path.open('rb') as f:
        for j, index in enumerate(indices[:16]):
            if index>=len(entries): continue
            offset,size=entries[index]
            f.seek(offset)
            im=Image.open(io.BytesIO(f.read(size)))
            if crop: im=im.crop((300,290,1000,590))
            im.thumbnail((320,180))
            x,y=(j%4)*320,(j//4)*205
            canvas.paste(im,(x,y))
            draw.text((x+5,y+182),f'{path.stem} frame {index} / {index/60:.2f}s',fill='white')
    canvas.save(dest)
    return len(entries)

if __name__=='__main__':
    for name in ['before','after']:
        count=sheet(OUT/f'{name}.avi',[115,125,135,145,155,165,175,185,245,255,265,275,340,350,360,370],OUT/f'{name}_frames.jpg',True)
        trace=json.loads((OUT/f'{name}.json').read_text())
        print(name,'frames',count,'forced_roll_samples',sum(s['clip']=='roll_landing' for s in trace),'dash_samples',sum(s['clip']=='aerial_dash' for s in trace))
    old=OUT.parent/'录屏/movie3.avi'
    entries=frames(old)
    print('old frames',len(entries))
    sheet(old,list(range(90,90+16*6,6)),OUT/'old_continuous.jpg')
    # Same input sequence side by side at original playback speed (every 3rd frame).
    indices={name:frames(OUT/f'{name}.avi') for name in ['before','after']}
    clips=[]
    for index in range(115,226,3):
        canvas=Image.new('RGB',(960,250),(20,30,38))
        draw=ImageDraw.Draw(canvas)
        for side,name in enumerate(['before','after']):
            offset,size=indices[name][index]
            with (OUT/f'{name}.avi').open('rb') as f:
                f.seek(offset)
                im=Image.open(io.BytesIO(f.read(size))).crop((250,260,1000,590))
                im.thumbnail((480,215))
                canvas.paste(im,(side*480,30))
                draw.text((side*480+12,8),f'{name.upper()} - same inputs - {index/60:.2f}s',fill='white')
        clips.append(canvas)
    clips[0].save(OUT/'comparison.gif',save_all=True,append_images=clips[1:],duration=50,loop=0)

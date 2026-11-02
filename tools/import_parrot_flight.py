"""Pack the one-pass sprite edit, normalize once, then stabilize its cheek anchor.

No artwork is painted here. The supplied sprite-pipeline normalizer handles the
shared scale; the last translation keeps flight frames from bobbing with wingtips.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'homeing-star-temp-assert/ProductionArt/chapter_1_wind/20261103/parrot_flight'
SKILL = Path('D:/CodexData/.codex/plugins/cache/openai-curated-remote/game-studio/0.1.2')
SOURCE = Path(sys.argv[1])
RAW.mkdir(parents=True, exist_ok=True)
shutil.copyfile(SOURCE, RAW / 'flight_raw.png')
image = Image.open(SOURCE).convert('RGBA')
# Transparent valleys between the eight generated birds, measured on the raw.
CUTS = [0, 280, 541, 865, 1130, 1356, 1615, 1886, 2172]
CHEEKS = [(183.5,316.5),(446,321),(735.5,319.5),(1011.5,320.5),
          (1286.5,319),(1551.5,319.5),(1808.5,321),(2055.5,320)]
assert image.size == (2172,724), image.size
packed = Image.new('RGBA', (384*8,724))
bounds = []
offsets = []
for i in range(8):
    part = image.crop((CUTS[i],0,CUTS[i+1],724))
    x = (384-part.width)//2
    packed.alpha_composite(part,(384*i+x,0))
    bbox = part.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
    assert bbox
    bounds.append(bbox)
    offsets.append(x)
packed.save(RAW/'packed_strip.png')
subprocess.run([sys.executable,str(SKILL/'scripts/normalize_sprite_strip.py'),
               '--input',str(RAW/'packed_strip.png'),'--out-dir',str(RAW/'normalized'),
               '--frames','8','--frame-size','88'],check=True)
scale = min(88/max(b[2]-b[0] for b in bounds),88/max(b[3]-b[1] for b in bounds))
sheet = Image.new('RGBA',(96*8,96))
metadata = {'source':str(SOURCE),'shared_scale':scale,'face_anchor':[59,35],'frames':[]}
frames = RAW/'frames'
frames.mkdir(exist_ok=True)
for i,bbox in enumerate(bounds):
    normalized = Image.open(RAW/'normalized'/f'{i+1:02}.png').convert('RGBA')
    width,height = round((bbox[2]-bbox[0])*scale),round((bbox[3]-bbox[1])*scale)
    # Match the normalizer's rounded common scale; only translate its result.
    eye_x = (88-width)//2 + (CHEEKS[i][0]-CUTS[i]-bbox[0])*width/(bbox[2]-bbox[0])
    eye_y = 88-height + (CHEEKS[i][1]-bbox[1])*height/(bbox[3]-bbox[1])
    dx,dy = round(59-eye_x),round(35-eye_y)
    frame = Image.new('RGBA',(96,96))
    frame.alpha_composite(normalized,(dx,dy))
    before = normalized.getchannel('A').histogram()
    after = frame.getchannel('A').histogram()
    assert before[1:]==after[1:], f'Frame {i+1} clips after anchor correction'
    frame.save(frames/f'{i+1:02}.png')
    sheet.alpha_composite(frame,(i*96,0))
    metadata['frames'].append({'raw_bounds':bbox,'translation':[dx,dy]})
output = ROOT/'homeing-star-game/assets/levels/chapter_1/wind/props/parrot_fly_96x96_8f.png'
sheet.save(output)
(RAW/'normalization.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
subprocess.run([sys.executable,str(SKILL/'scripts/render_sprite_preview_sheet.py'),
               '--frames-dir',str(frames),'--out',str(RAW/'flight_preview.png'),
               '--columns','8'],check=True)
images=[Image.open(frames/f'{i+1:02}.png').convert('RGBA') for i in range(8)]
images[0].save(RAW/'flight_preview.gif',save_all=True,append_images=images[1:],
               duration=[40,40,40,40,60,60,60,60],loop=0,disposal=2,transparency=0)
print(output)

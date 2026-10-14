"""Copy unmodified Frogger strips; audit 128px idle / 384px action cells."""
from pathlib import Path
import argparse
import shutil
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=Path(r'E:\download\Bosses_Frogger\Frogger'))
parser.add_argument('--audit-only', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
target = root / 'homeing-star-game/assets/sideview/characters/frogger'
audit = root / 'homeing-star-test/artifacts/frogger-art'
audit.mkdir(parents=True, exist_ok=True)
if not args.audit_only:
    target.mkdir(parents=True, exist_ok=True)
for action in ['idle', 'move', 'tongue', 'spit', 'heal', 'hurt']:
    source = args.source / f'frogger_{action}.png'
    strip = Image.open(source).convert('RGBA')
    width = 128 if action == 'idle' else 384
    assert strip.height == 128 and strip.width % width == 0
    count = strip.width // width
    columns = 4 if action == 'idle' else 3
    sheet = Image.new('RGB', (width*columns, ((count+columns-1)//columns)*148), '#404044')
    draw = ImageDraw.Draw(sheet)
    boxes = []
    for frame in range(count):
        tile = strip.crop((frame*width, 0, (frame+1)*width, 128))
        boxes.append(tile.getbbox())
        x, y = (frame % columns)*width, (frame // columns)*148
        sheet.paste(tile, (x,y+20), tile)
        draw.text((x+3,y+3), f'{action} F{frame:02}', fill='white')
    sheet.save(audit / f'{action}.png')
    print(action, count, boxes)
    if not args.audit_only:
        shutil.copy2(source, target / source.name)

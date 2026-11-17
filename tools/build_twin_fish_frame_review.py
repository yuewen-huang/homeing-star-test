"""Contact every changed drawing in a native capture; never skip source poses."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

p = argparse.ArgumentParser()
p.add_argument('--trace', type=Path, required=True)
p.add_argument('--captures', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
data = json.loads(a.trace.read_text(encoding='utf-8'))
records = data['frames']
chosen = []
last = None
for r in records:
    if not (a.captures / f'movie_{r["index"]:03}.png').exists(): break
    key = tuple((r[c]['frame'], r[c]['mirror']) for c in ('white', 'black'))
    if key != last:
        chosen.append(r)
        last = key
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 14)
for page in range(math.ceil(len(chosen) / 16)):
    sheet = Image.new('RGB', (2048, 4 * 256), '#282c2d')
    draw = ImageDraw.Draw(sheet)
    for slot, r in enumerate(chosen[page * 16:(page + 1) * 16]):
        x, y = slot % 4 * 512, slot // 4 * 256
        im = Image.open(a.captures / f'movie_{r["index"]:03}.png')
        sheet.paste(im.crop((160, 150, 1120, 555)).resize((512, 216)), (x, y + 40))
        w, b = r['white'], r['black']
        draw.text((x+5, y+3), f'#{r["index"]:03}  {r["time"]:.3f}s  W {w["action"]} F{w["frame"]}', font=font, fill='white')
        draw.text((x+5, y+21), f'B {b["action"]} F{b["frame"]}   yaw W {math.degrees(w["heading"])%360:.0f} / B {math.degrees(b["heading"])%360:.0f}', font=font, fill='#a3d6e8')
    sheet.save(a.out / f'changes_{page:02}.png')
(a.out / 'trace.json').write_text(json.dumps(data), encoding='utf-8')
def delta(b, c): return (b-c+math.pi)%(2*math.pi)-math.pi
report = []
for color in ('white', 'black'):
    report.append(color.upper())
    events = []
    for n, r in enumerate(records):
        f = r[color]
        if f['turning'] and (n == 0 or not records[n-1][color]['turning']):
            events.append(f'{r["time"]:.3f}s {f["action"]} mirror={f["mirror"]}')
    report.extend(events)
    peak = sorted(((abs(math.degrees(delta(records[n][color]['heading'], records[n-1][color]['heading'])))*60, records[n]['time'], records[n][color]['action']) for n in range(1,len(records))), reverse=True)[:8]
    report.append('peak yaw deg/s: '+str(peak))
(a.out / 'angular_audit.txt').write_text('\n'.join(report), encoding='utf-8')
print(f'{len(chosen)} changed drawings, {math.ceil(len(chosen)/16)} sheets')
print('\n'.join(report))

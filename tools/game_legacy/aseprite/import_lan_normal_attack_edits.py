"""Import Lan's edited normal-attack layers and refit their active-frame hitboxes.

Run from anywhere: python tools/aseprite/import_lan_normal_attack_edits.py
Only attack_2x_1 and attack_2x_2 are imported; attack_1x remains the reference.
"""
from pathlib import Path
import argparse
import json
import math
import struct
import subprocess
import tempfile
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'PendingArt/character/\u4e3b\u89d2-\u5c9a/\u624b\u52a8\u4f5c\u4e1a\u533a'
BODY_LAYER = '\u4eba\u7269\u52a8\u4f5c'
FX_LAYER = '\u653b\u51fb\u7279\u6548'

def fit_capsules(image):
    alpha = np.asarray(image)[:, :, 3]
    specs = []
    # Fit substantial blade pixels in three bands; detached wisps do not extend damage.
    for low, high in ((0, 20), (20, 40), (40, 61)):
        y, x = np.where(alpha[low:high] >= 128)
        if len(x) < 12:
            continue
        points = np.column_stack((x + 0.5, y + low + 0.5))
        origin = points.mean(axis=0)
        values, axes = np.linalg.eigh(np.cov(points.T))
        axis = axes[:, -1]
        if axis[0] < 0:
            axis = -axis
        normal = np.array([-axis[1], axis[0]])
        along = (points - origin) @ axis
        across = (points - origin) @ normal
        amin, amax = np.percentile(along, (2, 98))
        nmin, nmax = np.percentile(across, (2, 98))
        center = origin + axis * (amin + amax) / 2 + normal * (nmin + nmax) / 2
        diameter = max(4.0, nmax - nmin + 2.0)
        length = max(diameter, amax - amin + 2.0)
        specs.append([round(float(center[0]), 2), round(float(center[1]), 2), round(float(length), 2), round(float(diameter), 2), round(math.atan2(axis[1], axis[0]), 4)])
    assert specs
    return specs

def pack(frames, columns, path):
    width, height = frames[0].size
    sheet = Image.new('RGBA', (width * columns, height * math.ceil(len(frames) / columns)))
    for i, image in enumerate(frames):
        sheet.paste(image, ((i % columns) * width, (i // columns) * height))
    sheet.save(path)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--aseprite', default='E:/Aseprite/Aseprite.exe')
    parser.add_argument('--review-dir', type=Path)
    args = parser.parse_args()
    replacements = {}
    report = {}
    with tempfile.TemporaryDirectory(prefix='lan-attack-import-') as scratch:
        scratch = Path(scratch)
        for name, count, delay in [('attack_2x_1', 6, 0), ('attack_2x_2', 10, 2)]:
            source = SOURCE / f'{name}.aseprite'
            data = source.read_bytes()
            assert struct.unpack_from('<5H', data, 4) == (0xA5E0, count, 180, 61, 32), source
            # Durations and frame count must agree with the existing gameplay timeline.
            pos = 128
            for i in range(count):
                assert struct.unpack_from('<H', data, pos + 8)[0] == 40
                pos += struct.unpack_from('<I', data, pos)[0]
            layers = {}
            for layer in (BODY_LAYER, FX_LAYER):
                exported = scratch / f'{name}-{len(layers)}.png'
                subprocess.run([args.aseprite, '--batch', '--layer', layer, str(source), '--sheet', str(exported), '--sheet-type', 'horizontal'], check=True, stdout=subprocess.DEVNULL)
                strip = Image.open(exported).convert('RGBA')
                assert strip.size == (180 * count, 61)
                layers[layer] = [strip.crop((i * 180, 0, (i + 1) * 180, 61)) for i in range(count)]
            bodies = [image.crop((60, 1, 172, 60)) for image in layers[BODY_LAYER]]
            # The canvas grew 52px to the left. Crop only transparent body padding.
            for image in layers[BODY_LAYER]:
                outside = image.copy()
                outside.paste((0, 0, 0, 0), (60, 1, 172, 60))
                assert outside.getchannel('A').getbbox() is None, 'Body artwork outside its runtime frame'
            fx = layers[FX_LAYER][delay:delay + 6]
            for i, image in enumerate(layers[FX_LAYER]):
                if i < delay or i >= delay + 6:
                    assert image.getchannel('A').getbbox() is None
            body_path = ROOT / f'assets/sideview/characters/lan/attack/{name}_palette_base.png'
            fx_path = ROOT / f'assets/sideview/effects/lan_attacks/{name}/{name}_fx_180x61_6f.png'
            pack(bodies, count // 2, body_path)
            pack(fx, 3, fx_path)
            specs = {i: fit_capsules(fx[i]) for i in (1, 2, 3, 4)}
            # -90 - 12 = -102: preserves the original -50 top-left minus the 52px extension.
            lines = [f'static func {name}() -> AttackEffectDefinition:', '\t# Capsules fitted to edited blade pixels; preserve active frames and damage cadence.', f'\treturn _definition({name.upper()}_TEXTURE, Vector2i(180, 61), 6, 25.0, Vector2(12.0, -3.5),', '\t\t{']
            for i, shapes in specs.items():
                rendered = ', '.join(f'_capsule(Vector2({x}, {y}), {length}, {diameter}, {angle})' for x, y, length, diameter, angle in shapes)
                lines.append(f'\t\t\t{i}: [{rendered}],')
            lines.append('\t\t})')
            replacements[name] = '\n'.join(lines)
            report[name] = dict(canvas=[180,61], body_crop=[60,1,112,59], effect_frames=list(range(delay+1,delay+7)), hitboxes=specs)
            if args.review_dir:
                args.review_dir.mkdir(parents=True, exist_ok=True)
                review = Image.new('RGBA', (540, 182), (30, 32, 38, 255))
                for i in range(6):
                    composite = layers[BODY_LAYER][i+delay].copy()
                    composite.alpha_composite(fx[i])
                    draw = ImageDraw.Draw(composite)
                    for x,y,length,diameter,angle in specs.get(i, []):
                        axis=np.array([math.cos(angle), math.sin(angle)])
                        normal=np.array([-axis[1],axis[0]])
                        half=(length-diameter)/2
                        polygon=[]
                        for sign,start in ((1,-math.pi/2),(-1,math.pi/2)):
                            c=np.array([x,y])+axis*half*sign
                            for t in np.linspace(start,start+math.pi,20):
                                p=c+axis*math.cos(t)*diameter/2+normal*math.sin(t)*diameter/2
                                polygon.append(tuple(p))
                        draw.line(polygon+[polygon[0]],fill=(255,90,90,255),width=1)
                    review.paste(composite, ((i%3)*180, (i//3)*91+25))
                    ImageDraw.Draw(review).text(((i%3)*180+4,(i//3)*91+6),f'FX {i} / body {i+delay}',fill='white')
                review.resize((1620,546),Image.Resampling.NEAREST).save(args.review_dir/f'{name}-hitboxes.png')
    catalog = ROOT/'scripts/sideview/lan_attack_effect_catalog.gd'
    text = catalog.read_text(encoding='utf-8')
    for name, replacement in replacements.items():
        start = text.index(f'static func {name}()')
        end = text.index('\n\n\nstatic func ', start)
        text = text[:start] + replacement + text[end:]
        text = text.replace(f'{name}_fx_128x61_6f.png', f'{name}_fx_180x61_6f.png')
    catalog.write_text(text,encoding='utf-8')
    if args.review_dir:
        (args.review_dir/'lan-attack-import.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('Imported both edited attacks; preserved body anchors, timeline and active damage frames.')

if __name__ == '__main__':
    main()

"""Normalize generated arena art, retain sources, and build review previews.

Run with a JSON list of {name, source, prompt, transparent} records.
Ground textures are cropped at the first solid horizontal row, scaled uniformly
to 1280 px wide, then cropped to the existing 165 px floor depth.
"""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/sideview/environment/chapter_1_boss_rooms'
SIZE = (1280, 720)


def main():
    jobs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    (OUT / 'source').mkdir(parents=True, exist_ok=True)
    manifest = []
    for job in jobs:
        name = job['name']
        raw = OUT / 'source' / (name + '_raw_v1.png')
        shutil.copy2(job['source'], raw)
        im = Image.open(raw).convert('RGBA')
        surface = None
        if name.endswith('_ground'):
            alpha = im.getchannel('A')
            surface = next(y for y in range(im.height)
                           if sum(v >= 240 for v in alpha.crop((0,y,im.width,y+1)).getdata()) >= im.width * .995)
            im = im.crop((0, surface, im.width, im.height))
            height = round(im.height * 1280 / im.width)
            if height < 165:
                raise ValueError(f'{name}: insufficient solid ground depth {height}')
            im = im.resize((1280,height), Image.Resampling.LANCZOS).crop((0,0,1280,165))
            # Collision surface starts at the first solid row; discarded grass
            # does not become a false elevated walkable silhouette.
        else:
            im = ImageOps.fit(im, SIZE, Image.Resampling.LANCZOS)
        target = OUT / (name + '_v1.png')
        im.save(target)
        manifest.append({**job, 'source': 'source/' + raw.name,
                         'file': target.name, 'size': list(im.size),
                         'source_floor_row': surface, 'floor_y': 555 if surface is not None else None})
    (OUT / 'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    make_previews()
    print(f'Prepared {len(manifest)} arena assets in {OUT}')


def make_previews():
    far = {'wind':'chapter_1_wind/wind_canopy_far.png',
           'vine':'chapter_1_vine/vine_forest_far.png',
           'mist':'chapter_1_mist/mist_forest_far_01.png',
           'root':'chapter_1_root/layers/01_far_cavern.png'}
    core = {'wind':'upper_left','vine':'upper_right','mist':'lower_left','root':'lower_right'}
    previews = OUT / 'previews'
    previews.mkdir(exist_ok=True)
    board = Image.new('RGB',(1280,3*390),(22,30,32))
    for index,region in enumerate(['wind','vine','mist','root','final']):
        bg = OUT / 'final_far_v1.png' if region == 'final' else OUT.parent / far[region]
        im = ImageOps.fit(Image.open(bg).convert('RGBA'), SIZE, Image.Resampling.LANCZOS)
        if region == 'final':
            im.alpha_composite(Image.open(OUT / 'final_mid_v1.png').convert('RGBA'))
        im.alpha_composite(Image.open(OUT / (region+'_ground_v1.png')).convert('RGBA'),(0,555))
        if region in core:
            boss = Image.open(ROOT / 'assets/sideview/bosses/amethyst_tree_core' / (core[region]+'.png')).convert('RGBA')
            boss = boss.resize((555,555),Image.Resampling.LANCZOS)
            im.alpha_composite(boss,(725 if region in ['wind','mist'] else 0,0))
        else:
            im.alpha_composite(Image.open(OUT / 'final_fore_v1.png').convert('RGBA'))
        im.convert('RGB').save(previews / (region+'_composition_v1.jpg'),quality=92)
        thumb = im.convert('RGB').resize((640,360),Image.Resampling.LANCZOS)
        x,y = (index%2)*640,(index//2)*390
        board.paste(thumb,(x,y+30))
        ImageDraw.Draw(board).text((x+12,y+8),region.upper(),fill=(230,240,220))
    board.save(previews/'arena_contact_sheet_v1.jpg',quality=92)


if __name__ == '__main__':
    main()

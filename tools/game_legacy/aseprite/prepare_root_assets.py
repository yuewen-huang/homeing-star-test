"""Package generated root art. Only alpha trim, uniform scale and surface measurement."""
from pathlib import Path
import json
import shutil
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/sideview/environment/chapter_1_root'
SOURCE = Path(r'C:/Users/P6063166/.codex/generated_images/01a11976-33c0-7241-9040-d04376fa713c')
ART = {
    'root_ground_long': ('exec-7623affe-79c6-4b8c-8e85-8e11e74a3ad4.png', 420),
    'root_ground_wall': ('exec-f84d4c46-8442-4ae5-8632-efdce6d1eb08.png', 130),
    'root_light_fungus': ('exec-e575bc2e-5be5-4f6f-918c-0fab2b53fc75.png', 72),
    'root_floatwood': ('exec-04c3b51e-01aa-4037-a8de-ca22483e01f2.png', 260),
}

def pack():
    terrain = DEST / 'terrain/ground_v1'
    original = DEST / 'source'
    terrain.mkdir(parents=True, exist_ok=True)
    original.mkdir(parents=True, exist_ok=True)
    profiles = {}
    for name, (filename, width) in ART.items():
        source = SOURCE / filename
        if source.exists():
            shutil.copy2(source, original / (name + '.png'))
        else:
            source = original / (name + '.png')
        im = Image.open(source).convert('RGBA')
        im = im.crop(im.getchannel('A').getbbox())
        im = im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (im.width + 12, im.height + 12))
        canvas.alpha_composite(im, (6, 6))
        canvas.save(terrain / (name + '.png'))
        if name in ('root_ground_long', 'root_floatwood'):
            alpha = np.asarray(canvas)[:, :, 3]
            tops = [int(np.flatnonzero(alpha[:, x] > 180)[0]) for x in range(20, width - 8) if (alpha[:, x] > 180).any()]
            top = float(np.median(tops))
            profiles[name + '.png'] = dict(size=list(canvas.size), solid_x=[16, width - 4], median_top=top, top_left=top, top_right=top, fit_slope=0.0)
    # A shorter sibling retains the original scale and surface depth: crop a central section.
    im = Image.open(terrain / 'root_ground_long.png')
    short = im.crop((106, 0, 326, im.height))
    short.save(terrain / 'root_ground_short.png')
    top = profiles['root_ground_long.png']['median_top']
    profiles['root_ground_short.png'] = dict(size=list(short.size), solid_x=[6, 214], median_top=top, top_left=top, top_right=top, fit_slope=0.0)
    (terrain / 'surfaces.json').write_text(json.dumps(profiles, indent=2) + '\n', encoding='utf-8')
    print('Packaged root sprites:', [(p.name, Image.open(p).size) for p in terrain.glob('*.png')])

if __name__ == '__main__':
    pack()

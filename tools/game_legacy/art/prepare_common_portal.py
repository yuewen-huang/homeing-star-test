"""Normalize a generated neutral portal; preserve alpha and aspect ratio."""
import json
import shutil
import sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
out = root / 'assets/sideview/environment/common_portal'
(out / 'source').mkdir(parents=True, exist_ok=True)
(out / 'source/.gdignore').touch()
source = Path(sys.argv[1])
shutil.copy2(source, out / 'source/portal_frame_raw_v1.png')
im = Image.open(source).convert('RGBA')
# Ignore barely visible antialiased wisps when finding the actual frame bounds;
# cropping keeps the original alpha of all retained pixels.
box = im.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
im = im.crop(box)
factor = min(112 / im.width, 168 / im.height, 1.0)
im = im.resize((round(im.width * factor), round(im.height * factor)), Image.Resampling.LANCZOS)
canvas = Image.new('RGBA', (112, 168))
canvas.alpha_composite(im, ((112-im.width)//2, 168-im.height))
canvas.save(out / 'portal_frame_v1.png')
manifest = {'generator': 'built-in image_gen', 'prompt': sys.argv[2],
            'source': 'source/portal_frame_raw_v1.png', 'source_crop': list(box),
            'runtime': 'portal_frame_v1.png', 'runtime_size': [112,168],
            'anchor': 'bottom center', 'uniform_scale': factor,
            'colored_effects': 'procedural common_portal_aura.gdshader; never baked into frame'}
(out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print('Portal frame:', box, 'scale', factor, 'runtime', canvas.size)

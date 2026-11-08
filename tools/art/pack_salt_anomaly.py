"""Archive built-in imagegen sources and uniformly fit runtime sprites; no repainting."""
from pathlib import Path
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'homeing-star-temp-assert/ProductionArt/chapter_2_salt/anomaly'
GAME = ROOT / 'homeing-star-game'
TARGET = GAME / 'assets/levels/chapter_2_salt/environment/anomaly'
TARGET.mkdir(parents=True, exist_ok=True)
manifest = json.loads((SOURCE / 'prompts.json').read_text(encoding='utf-8'))
widths = dict(tools=210, shed=370, cart=240, binding=86, road=650, seam=42)
packing = {}
for name, width in widths.items():
    source = SOURCE / (name + '_source.png')
    shutil.copy2(manifest['sources'][name], source)
    image = Image.open(source).convert('RGBA')
    bounds = image.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
    image = image.crop(bounds)
    size = (width, round(image.height * width / image.width))
    image.resize(size, Image.Resampling.LANCZOS).save(TARGET / (name + '.png'))
    packing[name] = dict(crop=bounds, size=size)
comic = GAME / 'assets/shared/ui/comics/salt_cave_scroll_to_mirror_lake/01_scroll_discovery.png'
backup = SOURCE / '01_scroll_discovery_before.png'
if not backup.exists():
    shutil.copy2(comic, backup)
shutil.copy2(manifest['sources']['comic'], SOURCE / '01_scroll_discovery_source.png')
shutil.copy2(manifest['sources']['comic'], comic)
(SOURCE / 'packing.json').write_text(json.dumps(packing, indent=2), encoding='utf-8')
print(packing)

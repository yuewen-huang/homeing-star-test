"""Deterministic border-free crops; keep authored pixels and aspect ratios."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/title_opening/20261109_rework'
OUTPUT = ROOT / 'homeing-star-game/assets/shared/ui/comics/opening'
pages = [
    ('page_01.png', ['02_star.png', 'guardian_departure.png',
                     'lan_at_window.png', 'empty_arch.png']),
    ('page_02.png', ['01_harbor.png', 'dark_current.png',
                     'lantern_flicker.png', 'harbor_worker.png']),
    ('page_03.png', ['03_morning.png', 'lan_notices_current.png',
                     'lan_inspects_stone.png', '04_lan.png']),
]
boxes = [[9, 7, 830, 465], [844, 7, 1665, 465],
         [9, 478, 830, 933], [844, 478, 1665, 933]]
OUTPUT.mkdir(parents=True, exist_ok=True)
manifest = []
for source, names in pages:
    image = Image.open(SOURCE / source)
    assert image.size == (1672, 941), (source, image.size)
    for name, box in zip(names, boxes):
        image.crop(box).save(OUTPUT / name)
        manifest.append({'order': len(manifest) + 1, 'file': name,
                         'source': source, 'box': box})
(SOURCE / 'crops.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Imported twelve wordless opening panels without resampling')

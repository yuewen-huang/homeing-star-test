"""Promote the approved tiled-vine experiment to self-contained runtime assets."""
import json
from pathlib import Path
from PIL import Image

BASE = Path(__file__).resolve().parents[2]
VFX = BASE / 'homeing-star-game/assets/bosses/deer/body/human/vfx'
SOURCE = BASE / 'homeing-star-temp-assert/PendingArt/character/朽角巡林者/地涌藤鞭_局部贴图试验_20261013'
data = json.loads((SOURCE / 'motion.json').read_text(encoding='utf-8'))
data.update(active_frames=[11, 20], slam_frames=[11, 18], impact_frames=[16, 18])
encoded = json.dumps(json.dumps(data, ensure_ascii=False, separators=(',', ':')), ensure_ascii=False)
(VFX / 'vine_lash_motion.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = ' + encoded + '\n', encoding='utf-8')
Image.open(SOURCE / 'vine_bark_tile.png').save(VFX / 'vine_lash_bark.png')
Image.open(VFX / 'vine_ground_lash.png').crop((0, 0, 224, 224)).save(VFX / 'vine_lash_root.png')

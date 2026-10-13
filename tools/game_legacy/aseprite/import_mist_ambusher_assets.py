"""Copy the existing licensed boar/rat/bee animation sheets into runtime folders."""
from pathlib import Path
import shutil
import urllib.request
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
SPECS = {
 'boar': ('PendingArt/Legacy-Fantasy - High Forest 2.3/Mob/Boar', (48,32), [('Idle/Idle-Sheet.png','idle',4),('Run/Run-Sheet.png','run',6),('Hit-Vanish/Hit-Sheet.png','hit',4)]),
 'rat': ('PendingArt/monster/Enemy_Galore_I/Rat', (64,64), [('Rat_Idle.png','idle',4),('Rat_Run.png','run',8),('Rat_Attack.png','attack',8),('Rat_Hit.png','hit',4),('Rat_Death.png','death',8)]),
 'bee': ('PendingArt/Legacy-Fantasy - High Forest 2.3/Mob/Small Bee', (64,64), [('Fly/Fly-Sheet.png','idle',4),('Attack/Attack-Sheet.png','attack',4),('Hit/Hit-Sheet.png','hit',4)]),
}
for species,(folder,frame_size,animations) in SPECS.items():
 target=ROOT/'assets/sideview/monsters/mist'/species
 target.mkdir(parents=True,exist_ok=True)
 for filename,animation,count in animations:
  source=ROOT/folder/filename
  image=Image.open(source)
  assert image.width%frame_size[0]==0 and image.height%frame_size[1]==0
  assert image.width//frame_size[0]* (image.height//frame_size[1]) == count
  shutil.copyfile(source,target/f'{animation}.png')
 print('Imported',species)
audio=ROOT/'assets/sideview/audio/mist'
audio.mkdir(parents=True,exist_ok=True)
if not (audio/'boar_warning.mp3').exists():
 urllib.request.urlretrieve('https://cdn.freesound.org/previews/536/536746_1415754-hq.mp3',audio/'boar_warning.mp3')
(audio/'SOURCES.md').write_text('''# Mist ambush audio

`boar_warning.mp3`: publicly downloadable HQ preview of **Pig.ogg**, egomassive.
https://freesound.org/people/egomassive/sounds/536746/
License: CC0 1.0, as stated on the sound page.
Original recording credited there: Felix.Blume, "A Pig Grunting, Grumbling and Falling Asleep" (CC0).
https://creativecommons.org/publicdomain/zero/1.0/

Used for the boar warning only; routed to the SFX bus. No BGM changes.
''',encoding='utf-8')
(ROOT/'assets/sideview/monsters/mist/SOURCES.md').write_text('''# Mist ambusher art

Boar and Small Bee: existing project copies of Anokolisa's Legacy Fantasy / High Forest pack.
https://anokolisa.itch.io/sidescroller-pixelart-sprites-asset-pack-forest-16x16
Author's page states free commercial use and editing; full terms linked from that page.
Source folder: `PendingArt/Legacy-Fantasy - High Forest 2.3/Mob/`.

Rat: existing project asset `PendingArt/monster/Enemy_Galore_I/Rat/`.
No new third-party purchase or download was made for the rat.
The original project pack remains the source of its license documentation.

The PNGs are copied without recoloring or resizing. Species/frame counts are validated by
`tools/aseprite/import_mist_ambusher_assets.py`.
''',encoding='utf-8')

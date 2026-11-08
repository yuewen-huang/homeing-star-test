"""Pack native Studio frames without replacing its renderer."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[3]
source=ROOT/'homeing-star-test/artifacts/sandstorm-thomas/fx'
target=ROOT/'homeing-star-game/assets/bosses/sandstorm_fighter/fx/thomas'
target.mkdir(parents=True,exist_ok=True)
atlas=Image.new('RGBA',(640*8,384*8))
sheet=Image.new('RGB',(640*2,384*2),(37,40,40))
for i in range(60):
    frame=Image.open(source/f'frame_{i:03d}.png')
    box=frame.getbbox()
    assert box is None or (box[0]>0 and box[1]>0 and box[2]<640 and box[3]<384),(i,box)
    atlas.paste(frame,((i%8)*640,(i//8)*384))
for j,i in enumerate([3,18,35,55]):
    frame=Image.open(source/f'frame_{i:03d}.png')
    sheet.paste(frame,((j%2)*640,(j//2)*384),frame)
    ImageDraw.Draw(sheet).text(((j%2)*640+10,(j//2)*384+10),f'{i/30:.2f}s',fill='white')
atlas.save(target/'storm_ring_640x384_60f.png')
sheet.save(source.parent/'ring_review.png')
for name in ['combo.json','style.json','prompt.md']:
    (target/name).write_bytes((ROOT/'combat-vfx-studio/combos/sandstorm_thomas_wave'/name).read_bytes())
(target/'SOURCE.md').write_text('Native combat-vfx-studio sand arc streams with continuous rolling shear, overlapping dust sheets and sparse feathered grains. Optional stream_curl and stream_edge default to zero for other Studio presets. Radial display half-width remains 36px; collision and timing are unchanged. Editable source: combos/sandstorm_thomas_wave. 60 frames at 30 fps, 8x8 grid, 640x384 cell, origin (320,352), radius260. Runtime annular mesh preserves fixed band thickness while radius expands. No runtime sibling dependency. Rebuild with build_sandstorm_thomas.py, bake_sandstorm_thomas_studio.gd (Studio project), pack_sandstorm_thomas_fx.py. Previous sand_wave_384x448_96f.png is rejected and not loaded.\n',encoding='utf-8')
print('Packed native sand-wave atlas; no clipped alpha bounds.')

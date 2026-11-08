"""Pack native Studio renders; retain 1:1 world geometry and documented origin."""
import json
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[3]
target = ROOT / 'homeing-star-game/assets/bosses/sandstorm_fighter/fx/descent'
target.mkdir(parents=True, exist_ok=True)
for key in ['descent_quake', 'tiger_quake', 'dissipate', 'dissipate_idle', 'dissipate_punch', 'drop_trail']:
    files = sorted((ROOT / 'homeing-star-test/artifacts/sandstorm-skill/fx' / key).glob('frame_*.png'))
    assert len(files) == 60
    cell_h = 768 if key == 'drop_trail' else 384
    atlas = Image.new('RGBA', (8*512, 8*cell_h))
    for i, file in enumerate(files):
        frame = Image.open(file)
        bounds = frame.getbbox()
        assert bounds is None or (bounds[0]>0 and bounds[1]>0 and bounds[2]<512 and bounds[3]<cell_h), (key, i, bounds)
        atlas.paste(frame, ((i%8)*512, (i//8)*cell_h))
    atlas.save(target / (key+'.png'))
    for suffix in ['combo', 'style']:
        recipe = 'dissipate' if key.startswith('dissipate') else key
        source = ROOT / 'combat-vfx-studio/combos' / ('sandstorm_'+recipe) / (suffix+'.json')
        (target / (key+'_'+suffix+'.json')).write_bytes(source.read_bytes())
(target/'SOURCE.md').write_text('Native Godot bake of combat-vfx-studio quake and swarm sand renderers. Recipes: sandstorm_descent_quake, sandstorm_tiger_quake, sandstorm_dissipate, sandstorm_drop_trail. Sand uses zero dust, silhouette peel segments, small grains. Sprite erosion is composed offline from unchanged original poses.\n60 frames at 60 fps, 8 columns. Quake / dissolve variants: 512x384, origin (256,300). Trail: 512x768, origin (256,680), stationary world-space 420-pixel fall trajectory, spatially tapered tail with staggered particle fade. World scale 1.\nRebuild: tools/art/build_sandstorm_descent_profiles.py; bake_sandstorm_descent_studio.gd with Studio project; pack_sandstorm_descent_fx.py.\n', encoding='utf-8')
print('Packed 6 Studio renders, no clipped alpha bounds')

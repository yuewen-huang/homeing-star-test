"""Import only the accepted tail rig atlas; leave other signature effects unchanged."""
from pathlib import Path
import json, shutil
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
BAKE=ROOT/'homeing-star-test/artifacts/sandstorm-signature/tail_finisher_bake'
TARGET=ROOT/'homeing-star-game/assets/bosses/sandstorm_fighter/fx/signature'
STUDIO=ROOT/'combat-vfx-studio'
spec=json.loads((BAKE/'bake.json').read_text())
w,h=spec['cell'];cols=6;rows=(spec['frames']+cols-1)//cols
atlas=Image.new('RGBA',(w*cols,h*rows))
for i in range(spec['frames']):
    frame=Image.open(BAKE/f'frame_{i:03d}.png').convert('RGBA')
    assert frame.size==(w,h)
    atlas.paste(frame,((i%cols)*w,(i//cols)*h))
atlas.save(TARGET/'scorpion.png')
spec.update(columns=cols,rows=rows)
manifest=json.loads((TARGET/'manifest.json').read_text())
manifest['scorpion']=spec
(TARGET/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
shutil.copyfile(STUDIO/'studies/sandstorm_scorpion/tail_rig.json',TARGET/'scorpion_rig.json')
(TARGET/'scorpion_bake.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
(TARGET/'SOURCE.md').write_text('Signature sources: combat-vfx-studio/combos/sandstorm_signature_* for kick, arrival, peel and slam impact.\n'
    'Scorpion replacement: combat-vfx-studio/studies/sandstorm_scorpion/tail_stab.tscn and vfx/sand_scorpion_tail_study.gd. '
    'Accepted fixed-body articulated tail, sand grains + translucent dust, native transparent bake. '
    'Build/import: homeing-star-test/tools/art/bake_sand_scorpion_finisher.gd and import_sand_scorpion_finisher.py. '
    'scorpion_rig.json and scorpion_bake.json preserve the authored rig and phase/frame metadata. '
    'Historical scorpion_combo/style/prompt.json describe the retired swarm-tail source, not this atlas. '
    'Runtime samples wind/strike/hold/release directly from the owning attack phase; contact anchor is the tail tip at impact. '
    'No runtime sibling dependency.\n',encoding='utf-8')
print(f'Imported phase-locked tail: {spec["frames"]} frames, {atlas.size}, contact {spec["origin"]}')

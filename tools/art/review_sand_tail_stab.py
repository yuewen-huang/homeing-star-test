"""Mechanical constraints + consecutive pose review, not a combat-feel verdict."""
import json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'homeing-star-test/artifacts/sandstorm-scorpion-study'
FRAMES=OUT/'apparition/tail_stab'
rig=json.loads((ROOT/'combat-vfx-studio/studies/sandstorm_scorpion/tail_rig.json').read_text())
motion=json.loads((FRAMES/'motion.json').read_text())
assert all(row['parts'][0]==[0,0] for row in motion), 'Torso translated'
assert all(row['parts'][1]==rig['root'] for row in motion), 'Tail root translated'
max_error=max(abs(math.dist(row['parts'][i+1],row['parts'][i+2])-length)
              for row in motion for i,length in enumerate(rig['lengths']))
assert max_error<.001, max_error
hold=[row for row in motion if rig['strike_end']<=row['t']<=rig['hold_end']]
assert max(math.dist(hold[0]['tip'],row['tip']) for row in hold)<.001, 'Tip did not hold'
assert abs(hold[0]['tip'][1]-hold[0]['floor'])<.001, 'Ground contact missed'
wind=[row for row in motion if rig['wind_end']<=row['t']<=rig['strike_start']]
assert max(math.dist(wind[0]['tip'],row['tip']) for row in wind)<.001, 'Charge hold moved'
report=dict(torso_translation=0,root_translation=0,max_link_length_error=max_error,
            charge_hold_s=rig['strike_start']-rig['wind_end'],
            stab_s=rig['strike_end']-rig['strike_start'],
            contact_hold_s=rig['hold_end']-rig['strike_end'],tip=hold[0]['tip'],floor=hold[0]['floor'])
(OUT/'tail_stab_checks.json').write_text(json.dumps(report,indent=2))
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
board=Image.new('RGB',(1500,840),'#202523');draw=ImageDraw.Draw(board)
for i,n in enumerate([69,102,117,120,123,126,128,130,143,160]):
    im=Image.open(FRAMES/f'frame_{n:03d}.png').crop((340,35,955,680)).resize((300,315))
    x,y=(i%5)*300,(i//5)*420+40
    board.paste(im,(x,y))
    draw.text((x+15,y-28),f'{n/60:.3f} s',font=font,fill='#dbbc85')
board.save(OUT/'tail_stab_review.png')
# 30 FPS animated preview; the MP4 retains all native 60 FPS release frames.
images=[Image.open(FRAMES/f'frame_{n:03d}.png').crop((300,20,980,700)) for n in range(0,265,2)]
images[0].save(OUT/'tail_stab.gif',save_all=True,append_images=images[1:],
               duration=[40 if i%3==2 else 30 for i in range(len(images))],loop=0,optimize=False)
print(json.dumps(report))

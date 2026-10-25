"""Port the reviewed source clock and ribbon, excluding demo feedback and AI."""
from pathlib import Path
root = Path(__file__).resolve().parents[3]
src = root / 'smear-combo-demo/vfx'
dst = root / 'homeing-star-game/scripts/bosses/master'
s = (src/'smear_combo.gd').read_text(encoding='utf-8').replace('SmearCombo','MasterActionTimeline').replace('SmearLibrary','MasterActionLibrary')
(dst/'master_action_timeline.gd').write_text(s,encoding='utf-8')
s = (src/'smear_ribbon.gd').read_text(encoding='utf-8').replace('SmearRibbon','MasterBladeTrail').replace('SmearStyle.pixel','3.0').replace('SmearStyle.palette(&"normal")','[Color("effff8"), Color("a2eed8"), Color("43b9c6"), Color("285577")]').replace('res:'+'//vfx/smear_ribbon.gdshader','res://assets/bosses/master/fx/blade_trail.gdshader')
s = s.replace('var look := &"crescent"','var look := &"trail"')
(dst/'master_blade_trail.gd').write_text(s,encoding='utf-8')
(root/'homeing-star-game/assets/bosses/master/fx/blade_trail.gdshader').write_text((src/'smear_ribbon.gdshader').read_text(encoding='utf-8'),encoding='utf-8')
print('Ported source clock and blade renderer; no demo damage, feedback or AI')

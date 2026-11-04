"""Import the approved Studio materials; no editor stages, feedback or collision."""
from pathlib import Path
import hashlib
import json

WORK = Path(__file__).resolve().parents[3]
STUDIO = WORK / "combat-vfx-studio"
GAME = WORK / "homeing-star-game"
CODE = "scripts/bosses/deer/studio_vfx/"
ART = "assets/bosses/deer/fx/studio/"
FILES = {
    "vfx/swarm_effect.gd": CODE + "swarm_effect.gd",
    "vfx/swarm/materials.gd": CODE + "swarm/materials.gd",
    "vfx/quake/materials.gd": CODE + "swarm/colour_ramps.gd",
    "vfx/swarm/swarm.gdshader": ART + "swarm/swarm.gdshader",
    "vfx/swarm/piece_materials.gdshaderinc": ART + "swarm/piece_materials.gdshaderinc",
    "vfx/blade_cleave.gd": CODE + "blade_cleave.gd",
    "vfx/trajectory_ribbon.gd": CODE + "trajectory_ribbon.gd",
    "vfx/trajectory_ribbon.gdshader": ART + "trajectory_ribbon.gdshader",
    "vfx/magic/wind/gusts.gd": CODE + "magic/wind/gusts.gd",
    "vfx/magic/thunder/arcs.gd": CODE + "magic/thunder/arcs.gd",
    "vfx/magic/shaders/wind.gdshader": ART + "magic/shaders/wind.gdshader",
}


def adapt(name, text):
    for src, dst in FILES.items():
        text = text.replace("res://" + src, "res://" + dst)
    text = text.replace("res://vfx/magic/magic_art.gd", "res://" + CODE + "magic/magic_art.gd")
    text = text.replace("res://vfx/magic/shaders/noise.gdshaderinc", "res://" + ART + "magic/shaders/noise.gdshaderinc")
    if name in ("vfx/swarm_effect.gd", "vfx/magic/wind/gusts.gd"):
        text = text.replace("extends Node2D\n", 'extends Node2D\nconst RenderCaps = preload("res://scripts/vfx/studio_parry/render_caps.gd")\n', 1)
        text = text.replace("extends RefCounted\n", 'extends RefCounted\nconst RenderCaps = preload("res://scripts/vfx/studio_parry/render_caps.gd")\n', 1)
    if name == "vfx/swarm_effect.gd":
        text = text.replace('String(ComboStyle.data.get("quake_detail", "explosive"))', '"explosive"')
        text = text.replace('String(ComboStyle.data.get("quake_style", "real"))', '"real"')
        text = text.replace('maxf(ComboStyle.pixel, 1.0)', '1.0')
    if name == "vfx/swarm/swarm.gdshader":
        text = text.replace('const float FOCAL = 1400.0;', 'const float FOCAL = 1400.0;\nuniform vec2 projection_origin = vec2(0.0);\nuniform float floor_y = 10000.0;')
        text = text.replace('vec2(640.0, 360.0) + (p.xy - vec2(640.0, 360.0))', 'projection_origin + (p.xy - projection_origin)')
        text = text.replace('vec2 screen = to_screen(pos + local);', 'vec2 screen = to_screen(pos + local);\n\tif (screen.y > floor_y) { alive *= 1.0 - smoothstep(floor_y, floor_y + 12.0, screen.y); }')
        text = text.replace('void place(bool b,', '''// Optional deer ambient orbit. Zero keeps the imported Studio cloud unchanged.
uniform float leaf_orbit = 0.0;
uniform float leaf_orbit_layer = 0.0;
void place(bool b,''')
        original = '\t\tpos = at + dir * ext * pow(c.z, 0.7);'
        text = text.replace(original, original + '''
		float orbit_angle = a + t * (0.48 + c.w * 0.32);
		vec3 orbit = vec3(cos(orbit_angle) * ext.x * (0.7 + 0.3*c.z),
			z * ext.y * 0.55 + sin(orbit_angle*2.0+c.w*6.28)*18.0,
			sin(orbit_angle) * ext.z);
		pos = mix(pos, at + orbit, leaf_orbit);
		if (abs(leaf_orbit_layer) > 0.5) {
			alive *= mix(1.0, smoothstep(-0.15,0.15,sin(orbit_angle)*leaf_orbit_layer),leaf_orbit);
		}''')
    if name == "vfx/blade_cleave.gd":
        text = text.replace('colours = PixelSlash.palette_of(StringName(spec.palette))', 'colours = event.get("colours", [Color("f2efd2"), Color("bbc779"), Color("82913c"), Color("343f24")])')
        text = text.replace('_thickness = ComboStyle.thickness', '_thickness = float(event.get("thickness", 1.0))')
    if name == "vfx/trajectory_ribbon.gd":
        begin = text.index('\tif BladeLook.current()')
        end = text.index('\tblade.material = shader_material', begin)
        text = text[:begin] + '\tshader_material = ShaderMaterial.new()\n\tshader_material.shader = preload("res://' + ART + 'trajectory_ribbon.gdshader")\n\tfor i in 4: shader_material.set_shader_parameter("ink_%d" % i, palette[i])\n' + text[end:]
    return text


def main():
    records = []
    for src, dst in FILES.items():
        raw = (STUDIO / src).read_bytes()
        output = adapt(src, raw.decode("utf-8-sig").replace("\r\n", "\n"))
        target = GAME / dst
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(output, encoding="utf-8", newline="\n")
        records.append(dict(source=src, runtime=dst, source_sha256=hashlib.sha256(raw).hexdigest()))
    manifest = GAME / "assets/bosses/deer/fx/duel/studio_sources.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(dict(source_project="combat-vfx-studio", files=records,
        adaptations=["isolated palette and capability imports", "local swarm projection and floor fade",
                     "optional persistent leaf orbit with front and back depth layers",
                     "no editor targeting, stages, feedback or damage"]), indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(records)} Studio modules")


if __name__ == "__main__":
    main()

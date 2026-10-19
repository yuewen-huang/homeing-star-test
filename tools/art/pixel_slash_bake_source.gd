extends Node2D

## Procedural pixel slash (demo, 2026-10-16). A ribbon in three parts, all drawn into a
## low-resolution SubViewport and shown with nearest-neighbour scaling:
##   main band — the tip's recent path; older samples narrow and darken in steps and are
##               removed after `tail` seconds (no whole-trail alpha fade);
##   outer line — thin band(s) beyond a gap, same ageing;
##   tip edge  — a bright block on the newest part while the tip is moving.
## The swing ends by dropping the tip; the tail keeps narrowing until nothing is left.
## Shapes:
##   arc   — tip runs along an ellipse (radius × squash, rotated by tilt). squash < 1
##           reads as a horizontal swing seen from the side; any angle via start/end/tilt.
##   line  — tip runs straight from from_point to to_point: a thrust, with speed lines on
##           both sides and an arrow head.
##   burst — a ring and spikes opening at `center` (impacts, grab closures).
##   path  — one continuous stroke through a list of commands (see build_path): lines and
##           arcs joined tangent to each other, speed and width changing continuously, so
##           a whole combo flows without a stop or a kink; `jump` lifts the blade.
##   crescent — a fighting-game sword smear on the ellipse arc: thin at both ends and thick
##              in the middle, opens in `duration`, holds `hold`, then erodes from its old end
##              and thins over `fade`; layered body / mid / white core, an outer echo line,
##              an inner ghost one frame behind, and speed lines flung out as it fades.
##   star   — a hit spark: sharp rays (burst_spikes, alternating long/short) and a white
##            core opening in `duration`, holding `hold`, shrinking over `fade`.
##   sparks — pixel shards sprayed from `center` in a fan around spark_dir, under gravity;
##            with spark_streak off they are single drifting embers.
## Time only advances through advance(), so the owner can drive it with its action clock;
## `delay` holds the slash hidden for that much action time first.

signal finished

## World pixels per slash texel.
const PIXEL := 3.0
## Render density only; configure before adding to the tree. World geometry and time
## stay unchanged. The shared default remains 3; deer smears choose their own density.
var pixel_size := PIXEL:
	set(value): pixel_size = maxf(1.0, value)
## Largest step between two samples; keeps curves round at low frame rates.
const MAX_ARC_STEP := deg_to_rad(4.0)
const MAX_LINE_STEP := 0.04
const BURST_SPIKES := 8
## Path sampling distance in world pixels.
const PATH_STEP := 2.0
## Newest path points drawn as the bright leading edge.
const PATH_TIP_POINTS := 6
## Path stroke kinds: a striking blade, the thin blade carry between strikes, and a
## gathering wind-up that shimmers.
enum Kind { HIT, CARRY, CHARGE }
const KIND_NAMES := {"hit": Kind.HIT, "carry": Kind.CARRY, "charge": Kind.CHARGE}
## Period of the charge shimmer between the two brightest colours.
const CHARGE_FLICKER := 0.04

const PALETTES := {
	&"master_wind": [Color("eeeeee"), Color("00e0dd"), Color("009fe8"), Color("007fc3")],
	&"master_red": [Color("fff0dd"), Color("ff9c66"), Color("e2412f"), Color("6e1222")],
	&"master_gold": [Color("fffbe2"), Color("ffe189"), Color("e4ab35"), Color("80530f")],
	&"master": [Color("e8e4db"), Color("c5c7c8"), Color("6b8494"), Color("2b3948")],
	&"crab": [Color("f1f2e6"), Color("bee5d8"), Color("3cada8"), Color("174d54")],
	&"violet": [Color("fff4ff"), Color("f3b6ff"), Color("c25fe6"), Color("4f1c72")],
	&"normal": [Color("ffffff"), Color("d6f3ff"), Color("78c4ea"), Color("33618f")],
	&"red": [Color("fff0dd"), Color("ff9c66"), Color("e2412f"), Color("6e1222")],
	&"gold": [Color("fffbe2"), Color("ffe189"), Color("e4ab35"), Color("80530f")],
	&"green": [Color("f4ffe6"), Color("b9f27c"), Color("4fbf4a"), Color("1d5a2c")],
	# Body-derived bone/olive tones, graded for contrast against the forest backdrop.
	&"deer": [Color("eeeede"), Color("d8d4b4"), Color("8f945e"), Color("524c18")],
}

var shape := &"arc"
var wind_profile := &"down_cut"
## Arc: centre relative to this node; angles in radians (y down, so increasing turns
## clockwise on screen); radius is the outer edge.
var center := Vector2.ZERO
var start_angle := 0.0
var end_angle := PI * 0.5
var radius := 120.0
var squash := 1.0
var tilt := 0.0
## Line: the tip travels from_point → to_point.
var from_point := Vector2.ZERO
var to_point := Vector2(200, 0)
## Path: commands for build_path(), squashed vertically then rotated (radians).
var path: Array = []
var path_squash := 1.0
var path_tilt := 0.0
## Scales every path width; echo layers reuse the same path thinner.
var width_scale := 1.0
## Line: draw the arrow head while the tip moves (off for plain cut lines).
var arrow_head := true
## Crescent and star: seconds fully open, then seconds to vanish.
var hold := 0.04
var fade := 0.12
## Crescent speed lines flung outward as it fades.
const SPEED_LINES := 5
## Optional crescent layers. Defaults preserve other users of this shared effect.
var crescent_ghost := true
var crescent_speed_lines := true
var crescent_core := true
## Bright band thickness and outer echo opacity; shared defaults preserve existing looks.
var crescent_highlight := 0.62
var crescent_echo_alpha := 1.0
## Burst: ring spikes (0 for a plain ring such as a ground shockwave).
var burst_spikes := BURST_SPIKES
## Sparks: count, fan direction (radians, facing-forward) and half-spread, speed and life
## ranges, downward gravity (negative drifts up), fixed seed so a spray is repeatable.
var spark_count := 10
var spark_dir := 0.0
var spark_spread := deg_to_rad(35.0)
var spark_speed := Vector2(250, 650)
var spark_life := Vector2(0.18, 0.32)
var spark_gravity := 900.0
var spark_seed := 1
var spark_streak := true
## Converging shards start on a ring and arrive at `center` as their life ends (a gather).
var spark_converge := false
## Main band width at full strength (arc: inward from the outer edge; line: centred).
var width := 40.0
var line_gap := 6.0
var line_width := 4.0
var duration := 0.12
var tail := 0.16
var delay := 0.0
var palette: Array = PALETTES[&"normal"]
## 1 faces right; -1 mirrors the whole slash.
var facing := 1.0

var age := 0.0
var _samples: Array[Vector2] = []  # x = path parameter, y = birth time
var _swinging := true
var _viewport: SubViewport
var _canvas: Node2D
var _display: Sprite2D
var _path: Dictionary
var _next_point := 1
var _particles: Array[Dictionary] = []

## Turns path commands into dense points. Each command after "start" ends at its own
## `speed` (px/s) and `width`; both change linearly in time across the command, so speed
## is continuous at every joint. Commands:
##   {start: Vector2, heading: deg, speed, width}
##   {line: length, speed, width}
##   {arc: turn deg (positive turns clockwise on screen), r: radius, speed, width}
##   {jump: Vector2, heading, speed, width, wait: s} — lifts the blade (the trail breaks)
## Any drawing command may add burst: true (radius burst_radius) to mark its end point.
## Drawing commands may also set kind ("hit" default, "carry", "charge"), palette (a
## PALETTES key overriding the slash's own) and contact: fraction of the command where the
## blade lands, with stop (hit-stop seconds), shake, sparks (count), flash (seconds the
## stroke shows white) and finisher (bool) carried into the contact record; gather: true
## records the command's end (time, at) in `gathers`, where a wind-up peaks.
## Returns points, times, widths, strokes, kinds, commands (index per point), palettes
## (PALETTES key per point, &"" = the slash's own), normals, sides (+1 = outside of the
## turn is the normal's side), joints (last point index of each drawing command), bursts
## [{time, at, radius}], contacts [{time, at, dir, command, stop, shake, sparks, flash,
## finisher}] and total time.
static func build_path(commands: Array, squash := 1.0, tilt := 0.0) -> Dictionary:
	var points := PackedVector2Array()
	var times := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var strokes := PackedInt32Array()
	var kinds := PackedByteArray()
	var command_of := PackedInt32Array()
	var palettes: Array[StringName] = []
	var bursts: Array[Dictionary] = []
	var contacts: Array[Dictionary] = []
	var gathers: Array[Dictionary] = []
	var joints := PackedInt32Array()
	var pos := Vector2.ZERO
	var heading := 0.0
	var speed := 0.0
	var width := 8.0
	var time := 0.0
	var stroke := 0
	for command_index in commands.size():
		var c: Dictionary = commands[command_index]
		if c.has("start") or c.has("jump"):
			if c.has("jump"):
				time += float(c.get("wait", 0.05))
				stroke += 1
			pos = c.get("start", c.get("jump"))
			heading = deg_to_rad(float(c.get("heading", 0.0)))
			speed = float(c.speed)
			width = float(c.get("width", width))
			points.append(pos)
			times.append(time)
			widths.append(width)
			strokes.append(stroke)
			kinds.append(Kind.CARRY)
			command_of.append(command_index)
			palettes.append(&"")
			continue
		var end_speed := float(c.speed)
		var end_width := float(c.get("width", width))
		var turn := deg_to_rad(float(c.get("arc", 0.0)))
		var arc_radius := float(c.get("r", 0.0))
		var length := absf(turn) * arc_radius if c.has("arc") else float(c.line)
		var span := 2.0 * length / (speed + end_speed)
		var accel := (end_speed * end_speed - speed * speed) / (2.0 * length)
		var dir := Vector2.from_angle(heading)
		var pivot := pos - dir.orthogonal() * signf(turn) * arc_radius
		var count := maxi(1, ceili(length / PATH_STEP))
		var first := points.size()
		var kind: int = KIND_NAMES[String(c.get("kind", "hit"))]
		var colours := StringName(c.get("palette", &""))
		for k in range(1, count + 1):
			var dist := length * k / count
			var tau := dist / speed if absf(accel) < 0.000001 else (-speed + sqrt(maxf(speed * speed + 2.0 * accel * dist, 0.0))) / accel
			var p := pivot + (pos - pivot).rotated(signf(turn) * dist / arc_radius) if c.has("arc") else pos + dir * dist
			points.append(p)
			times.append(time + tau)
			widths.append(lerpf(width, end_width, tau / span))
			strokes.append(stroke)
			kinds.append(kind)
			command_of.append(command_index)
			palettes.append(colours)
		if c.has("contact"):
			var at := clampi(first + roundi(float(c.contact) * (count - 1)), first, points.size() - 1)
			var ahead := mini(at + 1, points.size() - 1)
			contacts.append({"time": times[at], "at": points[at], "dir": (points[ahead] - points[at - 1]).normalized(),
				"command": command_index, "stop": float(c.get("stop", 0.0)), "shake": float(c.get("shake", 0.0)),
				"sparks": int(c.get("sparks", 0)), "flash": float(c.get("flash", 0.0)), "finisher": bool(c.get("finisher", false))})
		heading += turn
		joints.append(points.size() - 1)
		pos = points[-1]
		time += span
		speed = end_speed
		width = end_width
		if c.get("burst", false): bursts.append({"time": time, "at": pos, "radius": float(c.get("burst_radius", 46.0))})
		if c.get("gather", false): gathers.append({"time": time, "at": pos})
	for i in points.size():
		points[i] = Vector2(points[i].x, points[i].y * squash).rotated(tilt)
	for b in bursts: b.at = Vector2(b.at.x, b.at.y * squash).rotated(tilt)
	for g in gathers: g.at = Vector2(g.at.x, g.at.y * squash).rotated(tilt)
	for contact in contacts:
		contact.at = Vector2(contact.at.x, contact.at.y * squash).rotated(tilt)
		contact.dir = Vector2(contact.dir.x, contact.dir.y * squash).rotated(tilt).normalized()
	var normals := PackedVector2Array()
	var sides := PackedFloat32Array()
	normals.resize(points.size())
	sides.resize(points.size())
	var side := 1.0
	for i in points.size():
		var before := i - 1 if i > 0 and strokes[i - 1] == strokes[i] else i
		var after := i + 1 if i + 1 < points.size() and strokes[i + 1] == strokes[i] else i
		normals[i] = (points[after] - points[before]).normalized().orthogonal()
		if before != i and after != i:
			var turning := (points[i] - points[before]).cross(points[after] - points[i])
			# A clockwise turn (positive cross, y down) has its outside on the normal's side
			# (orthogonal() points left of travel); keep the last side on straights.
			if absf(turning) > 0.02: side = signf(turning)
		sides[i] = side
	return {"points": points, "times": times, "widths": widths, "strokes": strokes, "kinds": kinds, "commands": command_of,
		"palettes": palettes, "normals": normals, "sides": sides, "joints": joints, "bursts": bursts, "contacts": contacts, "gathers": gathers, "total": time}

static func ease_swing(t: float) -> float:
	# Fast through the middle and a short settle at the end, like a struck blow.
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.4)

func configure(preset: Dictionary) -> Node2D:
	for key: String in preset:
		if key == "palette": palette = PALETTES[preset.palette]
		else: set(key, preset[key])
	return self

func _ready() -> void:
	age = -delay
	if shape == &"path": _path = build_path(path, path_squash, path_tilt)
	if shape == &"sparks": _particles = make_particles()
	var size := Vector2i.ONE * (ceili(_reach() / pixel_size) * 2 + 4)
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_canvas = Node2D.new()
	_canvas.position = Vector2(size) / 2.0
	_canvas.draw.connect(_draw_slash)
	_viewport.add_child(_canvas)
	_display = Sprite2D.new()
	_display.texture = _viewport.get_texture()
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.scale = Vector2.ONE * pixel_size
	add_child(_display)
	_samples.append(Vector2(_u0(), 0.0))

## Furthest any part of the slash can reach from this node, plus a margin.
func _reach() -> float:
	var outer := line_gap + line_width + 8.0
	match shape:
		&"wind_ribbons": return 330.0
		&"line": return maxf(from_point.length(), to_point.length()) + width + outer
		&"burst": return center.length() + radius * 1.6 + width + outer
		&"crescent": return center.length() + radius * maxf(1.0, squash) + line_gap * 3.0 + line_width + 48.0
		&"star": return center.length() + radius * 1.4 + width + outer
		&"sparks":
			var life := spark_life.y
			return center.length() + spark_speed.y * life + absf(spark_gravity) * life * life * 0.5 + outer
		&"path":
			var far := 0.0
			for p: Vector2 in _path.points: far = maxf(far, p.length())
			var widest := 0.0
			for w: float in _path.widths: widest = maxf(widest, w)
			return far + widest * width_scale + outer
	return center.length() + radius + outer

func _u0() -> float: return 0.0 if shape in [&"line", &"path"] else start_angle
func _u1() -> float: return 1.0 if shape == &"line" else end_angle

func is_done() -> bool:
	if shape in [&"burst", &"quake"]: return age >= duration + tail
	if shape == &"sparks": return age >= spark_life.y
	if shape in [&"crescent", &"star", &"wind_ribbons"]: return age >= duration + hold + fade
	return not _swinging and _samples.is_empty()

func tip_param() -> float:
	return lerpf(_u0(), _u1(), ease_swing(age / duration))

func advance(delta: float) -> void:
	if delta <= 0.0 or is_done(): return
	age += delta
	if age <= 0.0: return
	if shape == &"path":
		var times: PackedFloat32Array = _path.times
		while _next_point < times.size() and times[_next_point] <= age:
			_samples.append(Vector2(_next_point, times[_next_point]))
			_next_point += 1
		if _next_point >= times.size(): _swinging = false
		while not _samples.is_empty() and age - _samples[0].y >= tail:
			_samples.pop_front()
	elif shape in [&"arc", &"line"]:
		if _swinging:
			# The tip stops at `duration`; a long step must not stamp late births on the path.
			var target := tip_param()
			var last := _samples[-1].x
			var from_time := _samples[-1].y
			var to_time := minf(age, duration)
			var limit := MAX_LINE_STEP if shape == &"line" else MAX_ARC_STEP
			var steps := maxi(1, ceili(absf(target - last) / limit))
			for i in range(1, steps + 1):
				var t := float(i) / steps
				_samples.append(Vector2(lerpf(last, target, t), lerpf(from_time, to_time, t)))
			if age >= duration: _swinging = false
		while not _samples.is_empty() and age - _samples[0].y >= tail:
			_samples.pop_front()
	if is_instance_valid(_canvas): _canvas.queue_redraw()
	if is_done(): finished.emit()

## 1 for a fresh sample, falling to 0 as it reaches the end of the tail. Slightly
## faster than linear, so the old end tapers to a point instead of a blunt block.
func _strength(sample: Vector2) -> float:
	return pow(clampf(1.0 - (age - sample.y) / tail, 0.0, 1.0), 1.4)

## Path position at parameter u, offset d across it (arc: distance from the centre;
## line: signed distance from the axis). Returned in slash texels, mirrored by facing.
func _point(u: float, d: float) -> Vector2:
	var p: Vector2
	if shape == &"path":
		var points: PackedVector2Array = _path.points
		var normals: PackedVector2Array = _path.normals
		var i := clampi(int(u), 0, points.size() - 1)
		p = points[i] + normals[i] * d
	elif shape == &"line":
		var axis := to_point - from_point
		p = from_point + axis * u + axis.normalized().orthogonal() * d
	else:
		p = center + Vector2(cos(u) * d, sin(u) * d * squash).rotated(tilt)
	p.x *= facing
	return p / pixel_size

func _band(a: float, b: float, inner_a: float, outer_a: float, inner_b: float, outer_b: float, color: Color) -> void:
	if absf(outer_a - inner_a) < 0.5 and absf(outer_b - inner_b) < 0.5: return
	_canvas.draw_colored_polygon(PackedVector2Array([_point(a, inner_a), _point(a, outer_a), _point(b, outer_b), _point(b, inner_b)]), color)

func _shade(strength: float) -> Color:
	# Discrete steps rather than a smooth fade: new parts bright, old parts dark.
	if strength > 0.66: return palette[1]
	if strength > 0.33: return palette[2]
	return palette[3]

func _draw_slash() -> void:
	if age <= 0.0: return
	match shape:
		&"wind_ribbons": _draw_master_wind()
		&"burst": _draw_burst()
		&"quake": _draw_quake()
		&"sparks": _draw_sparks()
		&"crescent": _draw_crescent()
		&"star": _draw_star()
		&"line": _draw_line_trail()
		&"path": _draw_path_trail()
		_: _draw_arc_trail()

## Master wind (2026-10-19 restyle): drawn after the six kept painted frames (attack 1 /
## attack 2 F08–F10 and attack 2 F15–F17). This offline geometry never samples the PNGs;
## it copies their language: a blade is a bundle of parallel brush strokes in alternating
## inks with gaps between them and staggered ends; landings throw up a crown of spikes;
## comma-shaped wave curls and translucent cloud puffs trail the sweep; fading strokes
## break into dashes. Inks are the painted frames' own colours.
const MASTER_INK := {&"white": Color("ffffff"), &"pale": Color("e4e4e4"), &"cyan": Color("00f2fd"),
	&"mint": Color("69f0c7"), &"blue": Color("0197ec"), &"deep": Color("017cc6"), &"deeper": Color("0171b6")}
## Danger variants keep the same strokes in the shared red / gold.
const MASTER_RED_INK := {&"white": Color("fff0dd"), &"pale": Color("ffd9c0"), &"cyan": Color("ff9c66"),
	&"mint": Color("ffb38a"), &"blue": Color("e2412f"), &"deep": Color("a8262a"), &"deeper": Color("6e1222")}
const MASTER_GOLD_INK := {&"white": Color("fffbe2"), &"pale": Color("fff0c0"), &"cyan": Color("ffe189"),
	&"mint": Color("fff0a8"), &"blue": Color("e4ab35"), &"deep": Color("b07a1c"), &"deeper": Color("80530f")}
var _inks: Dictionary = MASTER_INK

## Elements per profile, in effect space (x forward, y down; the feet are at y = 160).
## strands: bezier [p0..p3], width, inks (one stroke each), delay. curl: centre, radius,
## turn (1 clockwise), delay. crown: base, height, spikes, delay. puffs: centres, radius.
func _master_elements() -> Array:
	match wind_profile:
		&"flip_chop":
			# 回身三连's last beat: over the top from high behind, chopping down in front;
			# the landing throws a spike crown, curls roll off behind.
			return [
				{"kind": "strands", "curve": [Vector2(-215,-30),Vector2(-160,-250),Vector2(225,-240),Vector2(232,118)], "width": 96.0,
					"inks": [&"mint", &"white", &"mint", &"blue", &"mint", &"deep"], "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(-150,-150),Vector2(-40,-262),Vector2(200,-232),Vector2(275,-40)], "width": 14.0,
					"inks": [&"cyan", &"blue"], "delay": 0.02},
				{"kind": "crown", "at": Vector2(232,160), "height": 150.0, "spikes": 9, "delay": 0.085},
				{"kind": "curl", "at": Vector2(-150,128), "radius": 40.0, "turn": -1.0, "delay": 0.05},
				{"kind": "curl", "at": Vector2(-88,140), "radius": 30.0, "turn": -1.0, "delay": 0.07},
			]
		&"return_lift":
			# 压步回锋's rising cut: puffs kicked up at the low start, a stroke bundle rising
			# to high in front, a curl where it leaves the ground.
			return [
				{"kind": "puffs", "at": [Vector2(-120,118),Vector2(-78,132),Vector2(-30,124)], "radius": 34.0, "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(-125,112),Vector2(-20,170),Vector2(250,-50),Vector2(110,-175)], "width": 84.0,
					"inks": [&"mint", &"white", &"blue", &"mint", &"deep"], "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(-60,140),Vector2(150,150),Vector2(285,-30),Vector2(205,-130)], "width": 12.0,
					"inks": [&"cyan", &"blue"], "delay": 0.02},
				{"kind": "curl", "at": Vector2(-150,100), "radius": 38.0, "turn": 1.0, "delay": 0.01},
			]
		&"front_cut":
			# 旋身顿斩's opening cut: forward and down across the chest.
			return [
				{"kind": "strands", "curve": [Vector2(-70,-150),Vector2(110,-215),Vector2(305,-85),Vector2(255,70)], "width": 80.0,
					"inks": [&"mint", &"white", &"blue", &"mint", &"deep"], "delay": 0.0},
				{"kind": "curl", "at": Vector2(-95,118), "radius": 32.0, "turn": -1.0, "delay": 0.04},
			]
		&"flat_spin":
			# 旋身顿斩's horizontal spin (wind only): a flat ring with puffs churned up inside.
			return [
				{"kind": "strands", "curve": {"ellipse": [Vector2(30,40), 215.0, 62.0, -200.0, 150.0]}, "width": 46.0,
					"inks": [&"mint", &"white", &"blue", &"deep"], "delay": 0.0},
				{"kind": "puffs", "at": [Vector2(-60,78),Vector2(-10,92),Vector2(45,84)], "radius": 30.0, "delay": 0.03},
			]
		&"blink_spin":
			# 瞬移回斩's reappearing spin: a low flat ring and a spike crown where he lands.
			return [
				{"kind": "strands", "curve": {"ellipse": [Vector2(20,92), 240.0, 52.0, -190.0, 160.0]}, "width": 44.0,
					"inks": [&"mint", &"white", &"blue", &"mint", &"deep"], "delay": 0.0},
				{"kind": "crown", "at": Vector2(150,160), "height": 90.0, "spikes": 7, "delay": 0.06},
				{"kind": "curl", "at": Vector2(-200,120), "radius": 30.0, "turn": -1.0, "delay": 0.05},
			]
		&"heavy_chop":
			# 瞬移回斩's delayed heavy: a tall, thick chop from high above into a big crown.
			return [
				{"kind": "strands", "curve": [Vector2(-50,-305),Vector2(120,-330),Vector2(265,-150),Vector2(175,150)], "width": 112.0,
					"inks": [&"mint", &"white", &"mint", &"blue", &"mint", &"deep"], "delay": 0.0},
				{"kind": "crown", "at": Vector2(175,160), "height": 170.0, "spikes": 11, "delay": 0.085},
				{"kind": "curl", "at": Vector2(-60,130), "radius": 38.0, "turn": -1.0, "delay": 0.06},
				{"kind": "curl", "at": Vector2(10,142), "radius": 28.0, "turn": -1.0, "delay": 0.08},
			]
		&"air_spin":
			# 旋空突坠's spin in the air (wind only): one fat C wrapping the body, from low
			# behind up over the head to its thickest at the low front, where the qi fly off.
			return [
				{"kind": "strands", "curve": {"ellipse": [Vector2(0,10), 165.0, 130.0, 140.0, 400.0]}, "width": 120.0,
					"inks": [&"mint", &"white", &"blue", &"mint", &"blue", &"deep"], "delay": 0.0},
				{"kind": "strands", "curve": {"ellipse": [Vector2(0,10), 192.0, 152.0, 170.0, 330.0]}, "width": 10.0,
					"inks": [&"cyan"], "delay": 0.02},
				{"kind": "strands", "curve": {"ellipse": [Vector2(0,10), 118.0, 94.0, 200.0, 380.0]}, "width": 12.0,
					"inks": [&"mint"], "delay": 0.03},
				{"kind": "curl", "at": Vector2(-150,112), "radius": 26.0, "turn": 1.0, "delay": 0.04},
			]
		&"sword_qi":
			# 旋空突坠's thrown qi (user reference): a big flat crescent across its flight (+x),
			# about twice the master's body wide, no trail (user 2026-10-19).
			return [
				{"kind": "strands", "curve": [Vector2(-40,-130),Vector2(85,-112),Vector2(85,112),Vector2(-40,130)], "width": 72.0,
					"inks": [&"mint", &"white", &"blue", &"mint", &"deep"], "delay": 0.0},
			]
		&"push_gust":
			# 旋空突坠's push off (user 2026-10-19: the geometric dome looked wrong): wind bursting
			# from his feet both ways in the kept painted frames' language. Each side fans into
			# curving strokes (a wave along the ground, an S at mid height, a hook rising, a thin
			# wisp) with fat fronts that do the pushing; puffs at his feet, curls on the fronts.
			return [
				{"kind": "strands", "curve": [Vector2(20,152),Vector2(140,108),Vector2(200,178),Vector2(318,128)], "width": 44.0,
					"inks": [&"mint", &"white", &"blue", &"deep"], "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(25,112),Vector2(150,38),Vector2(172,124),Vector2(296,52)], "width": 30.0,
					"inks": [&"white", &"mint", &"blue"], "delay": 0.015},
				{"kind": "strands", "curve": [Vector2(30,72),Vector2(62,-42),Vector2(192,42),Vector2(228,-66)], "width": 20.0,
					"inks": [&"mint", &"blue"], "delay": 0.03},
				{"kind": "strands", "curve": [Vector2(40,136),Vector2(150,172),Vector2(232,108),Vector2(282,150)], "width": 10.0,
					"inks": [&"cyan"], "delay": 0.02},
				{"kind": "curl", "at": Vector2(318,104), "radius": 26.0, "turn": 1.0, "delay": 0.08},
				{"kind": "curl", "at": Vector2(296,34), "radius": 18.0, "turn": 1.0, "delay": 0.09},
				{"kind": "strands", "curve": [Vector2(-20,152),Vector2(-140,108),Vector2(-200,178),Vector2(-318,128)], "width": 44.0,
					"inks": [&"mint", &"white", &"blue", &"deep"], "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(-25,112),Vector2(-150,38),Vector2(-172,124),Vector2(-296,52)], "width": 30.0,
					"inks": [&"white", &"mint", &"blue"], "delay": 0.015},
				{"kind": "strands", "curve": [Vector2(-30,72),Vector2(-62,-42),Vector2(-192,42),Vector2(-228,-66)], "width": 20.0,
					"inks": [&"mint", &"blue"], "delay": 0.03},
				{"kind": "strands", "curve": [Vector2(-40,136),Vector2(-150,172),Vector2(-232,108),Vector2(-282,150)], "width": 10.0,
					"inks": [&"cyan"], "delay": 0.02},
				{"kind": "curl", "at": Vector2(-318,104), "radius": 26.0, "turn": -1.0, "delay": 0.08},
				{"kind": "curl", "at": Vector2(-296,34), "radius": 18.0, "turn": -1.0, "delay": 0.09},
				{"kind": "puffs", "at": [Vector2(-110,150),Vector2(-50,148),Vector2(50,148),Vector2(110,150)], "radius": 26.0, "delay": 0.0},
			]
		&"plunge_crash":
			# 旋空突坠's landing: a big crown, wind streaking out along the ground both ways.
			return [
				{"kind": "crown", "at": Vector2(60,160), "height": 190.0, "spikes": 11, "delay": 0.0},
				{"kind": "strands", "curve": [Vector2(20,150),Vector2(120,128),Vector2(230,150),Vector2(335,146)], "width": 28.0,
					"inks": [&"mint", &"blue"], "delay": 0.02},
				{"kind": "strands", "curve": [Vector2(0,152),Vector2(-100,134),Vector2(-200,150),Vector2(-300,150)], "width": 24.0,
					"inks": [&"mint", &"blue"], "delay": 0.03},
				{"kind": "curl", "at": Vector2(255,132), "radius": 30.0, "turn": 1.0, "delay": 0.06},
				{"kind": "curl", "at": Vector2(-235,135), "radius": 28.0, "turn": -1.0, "delay": 0.07},
			]
		_:
			# Down cut (press-return draft): the painted F08 bundle with its landing crown.
			return [
				{"kind": "strands", "curve": [Vector2(-135,-125),Vector2(-15,-195),Vector2(240,-90),Vector2(200,118)], "width": 84.0,
					"inks": [&"mint", &"white", &"mint", &"blue", &"deep"], "delay": 0.0},
				{"kind": "crown", "at": Vector2(200,160), "height": 95.0, "spikes": 7, "delay": 0.08},
			]

func _draw_master_wind() -> void:
	if age >= duration+hold+fade: return
	_inks = MASTER_RED_INK if palette == PALETTES[&"master_red"] else (MASTER_GOLD_INK if palette == PALETTES[&"master_gold"] else MASTER_INK)
	for element: Dictionary in _master_elements():
		var local_age := age - float(element.delay)
		if local_age <= 0: continue
		var opening := ease_swing(local_age / duration)
		var erode := clampf((local_age-duration-hold)/fade,0,1)
		if erode >= 1: continue
		match element.kind:
			"strands": _master_strands(element, opening, erode)
			"crown": _master_crown(element, local_age, erode)
			"curl": _master_curl(element, opening, erode)
			"puffs": _master_puffs(element, opening, erode)

## A blade: a solid wave-shaped mass (thin tail, swelling to a blunt head at the end of the
## swing) in the base ink, with overlapping streaks inside it; the first ink is the outer
## edge, the last the inner edge. It erodes from the tail and breaks into dashes.
func _master_strands(element: Dictionary, opening: float, erode: float) -> void:
	var blade: float = float(element.width) * width / 32.0 * (1.0 - erode * 0.45)
	var first := erode * 0.85
	var last := opening
	if last - first < 0.01: return
	var silhouette := func(a: float) -> float: return blade * _wedge(a, last)
	_master_ribbon(element.curve, first, last, silhouette, 1.0, 0.0, _inks[element.get("base", &"blue")], erode, 0)
	var inks: Array = element.inks
	for i in inks.size():
		var lane := (float(i) + 0.5) / inks.size() - 0.5
		var stagger := 0.5 + 0.5 * sin(float(i) * 2.7 + 1.3)
		var s0 := maxf(first, 0.08 + 0.42 * stagger * absf(lane) * 2.0)
		var s1 := last * (1.0 - 0.05 * stagger)
		var colour: Color = _inks[inks[i]]
		if i % 3 == 2: colour.a = 0.9
		_master_ribbon(element.curve, s0, s1, silhouette, 0.18 + 0.14 * stagger, lane * 0.78, colour, erode, i + 1)
	if blade < 30.0: return
	var feathers := [[1.25, 0.10, 0.62, &"mint"], [-1.2, 0.08, 0.5, &"blue"], [1.55, 0.06, 0.42, &"mint"]]
	for f in feathers.size():
		var feather: Array = feathers[f]
		var flat := func(a: float) -> float: return blade * maxf(_wedge(a, last), 0.35)
		_master_ribbon(element.curve, first + 0.02 * f, minf(last, float(feather[2])), flat, float(feather[1]), float(feather[0]), _inks[feather[3]], erode, 20 + f)

## Thickness along a blade, relative to its current tip: thin tail, full at 82%, then a
## blunt head about half as thick.
func _wedge(a: float, tip: float) -> float:
	var x := clampf(a / maxf(tip, 0.01), 0.0, 1.0)
	if x < 0.82: return pow(x / 0.82, 1.25)
	return lerpf(1.0, 0.5, (x - 0.82) / 0.18)

## A band along `curve` between `first` and `last`: `frac` of the silhouette's thickness,
## its centre `rel` half-thicknesses off the curve. Eroding bands open stable gaps.
func _master_ribbon(curve: Variant, first: float, last: float, silhouette: Callable, frac: float, rel: float,
		colour: Color, erode: float, seed: int) -> void:
	const SAMPLES := 90
	for k in SAMPLES:
		var a := float(k) / SAMPLES
		var b := float(k + 1) / SAMPLES
		if b <= first or a >= last: continue
		if erode > 0.25 and (k + 7 * seed) % 19 in [5, 6, 7]: continue
		if erode > 0.55 and (k + 3 * seed) % 11 in [2, 3, 4, 5]: continue
		a = maxf(a, first)
		# Overlap the next segment a little: abutting quads leave single-texel holes on the
		# outside of a curve.
		b = minf(b + 0.6 / SAMPLES, last)
		var pa := _curve_at(curve, a)
		var pb := _curve_at(curve, b)
		var normal := (pb - pa).normalized().orthogonal()
		var sa: float = silhouette.call(a)
		var sb: float = silhouette.call(b)
		var wa := sa * frac * (1.0 + 0.15 * sin(a * 31.0 + float(seed)))
		var wb := sb * frac * (1.0 + 0.15 * sin(b * 31.0 + float(seed)))
		if maxf(wa, wb) < pixel_size * 0.8: continue
		wa = maxf(wa, pixel_size)
		wb = maxf(wb, pixel_size)
		var oa := sa * 0.5 * rel
		var ob := sb * 0.5 * rel
		var points := PackedVector2Array([(pa + normal * (oa + wa * 0.5)) / pixel_size, (pb + normal * (ob + wb * 0.5)) / pixel_size,
			(pb + normal * (ob - wb * 0.5)) / pixel_size, (pa + normal * (oa - wa * 0.5)) / pixel_size])
		if not Geometry2D.triangulate_polygon(points).is_empty(): _canvas.draw_colored_polygon(points, colour)

## A point along a blade path: a cubic bezier [p0..p3] or {"ellipse": [centre, rx, ry, from, to]}.
func _curve_at(curve: Variant, t: float) -> Vector2:
	if curve is Dictionary:
		var e: Array = curve.ellipse
		var angle := deg_to_rad(lerpf(float(e[3]), float(e[4]), t))
		return (e[0] as Vector2) + Vector2(cos(angle) * float(e[1]), sin(angle) * float(e[2]))
	return (curve[0] as Vector2).bezier_interpolate(curve[1], curve[2], curve[3], t)

## A crown of spikes thrown up where the blade lands (painted attack 1 F09/F10).
func _master_crown(element: Dictionary, local_age: float, erode: float) -> void:
	var grow := ease_swing(local_age / 0.05)
	var height: float = float(element.height) * grow * (1.0 - erode * 0.75)
	if height < 3.0: return
	var base: Vector2 = element.at
	var spikes: int = element.spikes
	var inks := [&"mint", &"blue", &"white", &"blue", &"cyan"]
	for i in spikes:
		var along := (float(i) + 0.5) / spikes
		var angle := deg_to_rad(lerpf(-158.0, -22.0, along) + 7.0 * sin(float(i) * 3.1))
		var long := i % 2 == 0
		var length := height * (1.0 if long else 0.55) * (0.75 + 0.25 * sin(float(i) * 1.7 + 0.4)) * (0.6 + 0.4 * sin(PI * along))
		var foot := base + Vector2((along - 0.5) * height * 0.9, 0)
		var dir := Vector2.from_angle(angle)
		var half := dir.orthogonal() * maxf(height * 0.11, pixel_size)
		var points := PackedVector2Array([(foot + half) / pixel_size, (foot + dir * length) / pixel_size, (foot - half) / pixel_size])
		if not Geometry2D.triangulate_polygon(points).is_empty(): _canvas.draw_colored_polygon(points, _inks[inks[i % 5]])

## A comma-shaped wave curl (painted attack 2 F15): a thick hooked head, a tapering tail.
func _master_curl(element: Dictionary, opening: float, erode: float) -> void:
	var r: float = float(element.radius) * (0.6 + 0.4 * opening)
	var turn: float = element.turn
	var sweep := deg_to_rad(210.0) * opening * (1.0 - erode * 0.6)
	var c: Vector2 = element.at
	_canvas.draw_circle((c + Vector2(0, -r)) / pixel_size, r * 0.5 * (1.0 - erode * 0.6) / pixel_size, _inks[&"blue"])
	for k in 18:
		var a := float(k) / 18.0
		var b := float(k + 1) / 18.0
		if b * sweep < 0.001: continue
		var ta: float = -PI * 0.5 + turn * a * sweep
		var tb: float = -PI * 0.5 + turn * b * sweep
		var na := Vector2.from_angle(ta)
		var nb := Vector2.from_angle(tb)
		var pa := c + na * r * (1.0 - a * 0.55)
		var pb := c + nb * r * (1.0 - b * 0.55)
		var wa := r * 0.95 * (1.0 - a * 0.85) * (1.0 - erode * 0.6)
		var wb := r * 0.95 * (1.0 - b * 0.85) * (1.0 - erode * 0.6)
		var points := PackedVector2Array([(pa + na * wa * 0.5) / pixel_size, (pb + nb * wb * 0.5) / pixel_size,
			(pb - nb * wb * 0.5) / pixel_size, (pa - na * wa * 0.5) / pixel_size])
		if not Geometry2D.triangulate_polygon(points).is_empty(): _canvas.draw_colored_polygon(points, _inks[&"blue"])

## Translucent cloud puffs with a bright rim (painted attack 2 F16).
func _master_puffs(element: Dictionary, opening: float, erode: float) -> void:
	var fill: Color = _inks[&"cyan"]
	fill.a = 0.3
	var centres: Array = element.at
	for i in centres.size():
		var r: float = float(element.radius) * (0.8 + 0.25 * sin(float(i) * 2.3)) * opening * (1.0 - erode * 0.8)
		if r < pixel_size: continue
		var c: Vector2 = centres[i]
		_canvas.draw_circle(c / pixel_size, r / pixel_size, fill)
		_canvas.draw_arc(c / pixel_size, r / pixel_size, PI * 1.05, PI * 1.95, 10, _inks[&"cyan"], 1.0)

func _draw_arc_trail() -> void:
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var sa := _strength(a)
		var sb := _strength(b)
		# The band narrows toward the outer edge as it ages; the inside is the darker rim.
		var wa := width * sa
		var wb := width * sb
		var shade := _shade((sa + sb) * 0.5)
		_band(a.x, b.x, radius - wa, radius, radius - wb, radius, shade)
		_band(a.x, b.x, radius - wa, radius - wa * 0.72, radius - wb, radius - wb * 0.72, palette[3] if shade != palette[3] else palette[3].darkened(0.3))
		_band(a.x, b.x, radius - maxf(wa * 0.18, pixel_size), radius, radius - maxf(wb * 0.18, pixel_size), radius, palette[0] if sa > 0.5 else palette[1])
		var line_r := radius + line_gap
		_band(a.x, b.x, line_r, line_r + line_width * sa, line_r, line_r + line_width * sb, palette[1] if sa > 0.5 else palette[2])
	if _swinging and _samples.size() >= 2:
		# Leading edge: the newest few degrees at full width in the brightest colour.
		var tip := _samples[-1].x
		var back := tip - signf(end_angle - start_angle) * deg_to_rad(9.0)
		_band(back, tip, radius - width * 0.9, radius + line_gap + line_width, radius - width, radius + line_gap + line_width, palette[0])

func _draw_line_trail() -> void:
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var sa := _strength(a)
		var sb := _strength(b)
		var ha := width * sa * 0.5
		var hb := width * sb * 0.5
		_band(a.x, b.x, -ha, ha, -hb, hb, _shade((sa + sb) * 0.5))
		_band(a.x, b.x, -ha, -ha * 0.55, -hb, -hb * 0.55, palette[3])
		var ca := maxf(ha * 0.3, pixel_size * 0.5)
		var cb := maxf(hb * 0.3, pixel_size * 0.5)
		_band(a.x, b.x, -ca, ca, -cb, cb, palette[0] if sa > 0.5 else palette[1])
		# Speed lines on both sides; they thin out with the tail like the band.
		for side: float in [-1.0, 1.0]:
			var ga := side * (ha + line_gap)
			var gb := side * (hb + line_gap)
			_band(a.x, b.x, ga, ga + side * line_width * sa, gb, gb + side * line_width * sb, palette[1] if sa > 0.5 else palette[2])
	if arrow_head and _swinging and _samples.size() >= 2:
		# Arrow head just ahead of the tip.
		var tip := _samples[-1].x
		var head := width * 0.9 / maxf((to_point - from_point).length(), 1.0)
		_canvas.draw_colored_polygon(PackedVector2Array([_point(tip + head, 0.0), _point(tip - head * 0.4, width * 0.7), _point(tip - head * 0.15, 0.0), _point(tip - head * 0.4, -width * 0.7)]), palette[0])

func _draw_burst() -> void:
	var t := clampf(age / duration, 0.0, 1.0)
	var fade := clampf((age - duration) / maxf(tail, 0.001), 0.0, 1.0)
	var r := radius * ease_swing(t)
	var thickness := maxf(width * (1.0 - fade) * (1.0 - 0.5 * t), pixel_size * 0.5)
	var colour: Color = palette[0] if fade < 0.3 else (palette[1] if fade < 0.66 else palette[2])
	var c := center
	c.x *= facing
	var steps := 24
	for i in steps:
		var a := Vector2.from_angle(TAU * i / steps) * Vector2(1.0, squash)
		var b := Vector2.from_angle(TAU * (i + 1) / steps) * Vector2(1.0, squash)
		var inner := maxf(r - thickness, 0.0)
		_canvas.draw_colored_polygon(PackedVector2Array([(c + a * inner) / pixel_size, (c + a * r) / pixel_size, (c + b * r) / pixel_size, (c + b * inner) / pixel_size]), colour)
	# Spikes: long thin rays just outside the ring, shrinking as it fades.
	var spike := radius * 0.55 * (1.0 - fade)
	if spike < pixel_size or burst_spikes <= 0: return
	for i in burst_spikes:
		var dir := Vector2.from_angle(TAU * i / burst_spikes + PI / burst_spikes)
		var side := dir.orthogonal() * maxf(thickness * 0.5, pixel_size)
		var base := c + dir * (r + line_gap)
		_canvas.draw_colored_polygon(PackedVector2Array([(base + side) / pixel_size, (base + dir * spike) / pixel_size, (base - side) / pixel_size]), palette[1] if fade < 0.5 else palette[2])

## Colours for a path point: its command's palette override, else the slash's own.
func _colours(index: int) -> Array:
	var key: StringName = (_path.palettes as Array)[index]
	return palette if key == &"" else PALETTES[key]

## Index of the command whose stroke is flashing white now, or -1.
func _flashing_command() -> int:
	for contact: Dictionary in _path.contacts:
		if contact.flash > 0.0 and age >= contact.time and age < contact.time + contact.flash: return contact.command
	return -1

func _draw_path_trail() -> void:
	var widths: PackedFloat32Array = _path.widths
	var strokes: PackedInt32Array = _path.strokes
	var sides: PackedFloat32Array = _path.sides
	var kinds: PackedByteArray = _path.kinds
	var commands: PackedInt32Array = _path.commands
	var flashing := _flashing_command()
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var ia := int(a.x)
		var ib := int(b.x)
		if strokes[ia] != strokes[ib]: continue  # the blade lifted between these points
		var sa := _strength(a)
		var sb := _strength(b)
		var ha := widths[ia] * width_scale * sa * 0.5
		var hb := widths[ib] * width_scale * sb * 0.5
		var side := sides[ib]
		var colours := _colours(ib)
		match kinds[ib]:
			Kind.CARRY:
				# The blade between strikes: one thin dim band, no rim, edge or line.
				_band(a.x, b.x, -ha, ha, -hb, hb, colours[2] if sa > 0.5 else colours[3])
				continue
			Kind.CHARGE:
				var shimmer := int(age / CHARGE_FLICKER) % 2 == 0
				_band(a.x, b.x, -ha, ha, -hb, hb, (colours[0] if shimmer else colours[1]) if sa > 0.4 else colours[2])
				if line_width > 0.0:
					_band(a.x, b.x, side * (ha + line_gap), side * (ha + line_gap + line_width * sa), side * (hb + line_gap), side * (hb + line_gap + line_width * sb), colours[1])
				continue
		if commands[ib] == flashing:
			# Contact flash: the whole stroke of the landing blow reads as one white cut.
			_band(a.x, b.x, -ha * 1.15, ha * 1.15, -hb * 1.15, hb * 1.15, colours[0])
			continue
		var shade: Color = colours[1] if (sa + sb) * 0.5 > 0.66 else (colours[2] if (sa + sb) * 0.5 > 0.33 else colours[3])
		_band(a.x, b.x, -ha, ha, -hb, hb, shade)
		# Dark rim on the inside of the turn, bright edge and thin line on the outside.
		_band(a.x, b.x, -side * ha, -side * ha * 0.44, -side * hb, -side * hb * 0.44, colours[3])
		_band(a.x, b.x, side * maxf(ha - maxf(ha * 0.36, pixel_size * 0.5), 0.0), side * ha, side * maxf(hb - maxf(hb * 0.36, pixel_size * 0.5), 0.0), side * hb, colours[0] if sa > 0.5 else colours[1])
		if line_width > 0.0:
			_band(a.x, b.x, side * (ha + line_gap), side * (ha + line_gap + line_width * sa), side * (hb + line_gap), side * (hb + line_gap + line_width * sb), colours[1] if sa > 0.5 else colours[2])
	if _swinging and _samples.size() >= 2:
		# Leading edge: the newest few points at full width in the brightest colour.
		for i in range(maxi(1, _samples.size() - PATH_TIP_POINTS), _samples.size()):
			var ia := int(_samples[i - 1].x)
			var ib := int(_samples[i].x)
			if strokes[ia] != strokes[ib]: continue
			var ha := widths[ia] * width_scale * 0.5
			var hb := widths[ib] * width_scale * 0.5
			_band(_samples[i - 1].x, _samples[i].x, -ha, ha, -hb, hb, _colours(ib)[0])

## The spray, fixed by spark_seed: velocity (facing-forward), life per shard.
func make_particles() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = spark_seed
	var list: Array[Dictionary] = []
	for i in spark_count:
		var angle := spark_dir + rng.randf_range(-spark_spread, spark_spread)
		list.append({"velocity": Vector2.from_angle(angle) * rng.randf_range(spark_speed.x, spark_speed.y),
			"life": rng.randf_range(spark_life.x, spark_life.y)})
	return list

func _spark_at(particle: Dictionary, t: float) -> Vector2:
	var p: Vector2 = center + particle.velocity * t + Vector2(0, spark_gravity) * t * t * 0.5
	if spark_converge: p = center + particle.velocity * (float(particle.life) - t)
	p.x = center.x * facing + (p.x - center.x) * facing
	return p / pixel_size

func _draw_sparks() -> void:
	for particle in _particles:
		var life: float = particle.life
		if age >= life: continue
		var fraction := age / life
		var colour: Color = palette[0] if fraction < 0.3 else (palette[1] if fraction < 0.65 else palette[2])
		var head := _spark_at(particle, age)
		if not spark_streak:
			_canvas.draw_rect(Rect2(head.floor(), Vector2.ONE), colour)
			continue
		# A short streak back along its motion, one texel thick.
		var tail_point := _spark_at(particle, maxf(age - 0.03, 0.0))
		var across := (head - tail_point).normalized().orthogonal() * 0.5
		if (head - tail_point).length() < 0.5:
			_canvas.draw_rect(Rect2(head.floor(), Vector2.ONE), colour)
			continue
		_canvas.draw_colored_polygon(PackedVector2Array([tail_point - across, head - across, head + across, tail_point + across]), colour)

## 0..1 through the fade (0 while opening or holding).
func _fade_fraction() -> float:
	return clampf((age - duration - hold) / maxf(fade, 0.001), 0.0, 1.0)

## Thickness profile along a crescent: zero at both ends, full in the middle.
static func lens(along: float) -> float:
	return pow(sin(PI * clampf(along, 0.0, 1.0)), 0.6)

## One crescent layer between fractions `from_s`..`to_s` of the arc. `inner` is how far the
## layer reaches in from the outer edge (`radius_at`), as a share of the lens thickness.
func _crescent_layer(from_s: float, to_s: float, radius_at: float, thickness: float, inner: float, colour: Color) -> void:
	if to_s - from_s <= 0.0005 or thickness * inner < 0.5: return
	var sweep := end_angle - start_angle
	var steps := maxi(2, ceili(absf(sweep) * (to_s - from_s) / deg_to_rad(3.0)))
	var outer := PackedVector2Array()
	var inside := PackedVector2Array()
	for i in steps + 1:
		var along := lerpf(from_s, to_s, float(i) / steps)
		var angle := start_angle + sweep * along
		outer.append(_point(angle, radius_at))
		inside.append(_point(angle, radius_at - thickness * inner * lens(along)))
	inside.reverse()
	var polygon := outer + inside
	if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty():
		_canvas.draw_colored_polygon(polygon, colour)

func _draw_crescent() -> void:
	var open := ease_swing(age / duration)
	var f := _fade_fraction()
	# Fading erodes the old end toward the tip and thins what is left.
	var from_s := pow(f, 0.8)
	var thick := width * (1.0 - f * 0.6)
	# Inner ghost: a smaller, darker copy one frame behind.
	var ghost := ease_swing((age - 1.0 / 60.0) / duration)
	if crescent_ghost: _crescent_layer(from_s, ghost, radius * 0.84, thick * 0.55, 1.0, palette[3])
	_crescent_layer(from_s, open, radius, thick, 1.0, palette[2])
	if f < 0.7: _crescent_layer(from_s, open, radius, thick, crescent_highlight, palette[1])
	if crescent_core and f < 0.35: _crescent_layer(from_s, open, radius, thick, 0.28, palette[0])
	# Outer echo line, a frame after the blade.
	if age > duration * 0.5 and f < 0.85:
		var line_r := radius + line_gap + line_width
		var echo_colour: Color = palette[1] if f < 0.4 else palette[2]
		echo_colour.a *= crescent_echo_alpha
		_crescent_layer(from_s, open * 0.96, line_r, line_width / maxf(lens(0.5), 0.01), 1.0, echo_colour)
	if f <= 0.0 or not crescent_speed_lines: return
	# Speed lines thrown off the outer edge as the cut fades.
	var sweep := end_angle - start_angle
	for k in SPEED_LINES:
		var along := (k + 0.5) / SPEED_LINES
		if along < from_s: continue
		var angle := start_angle + sweep * along
		var r0 := radius + line_gap * 2.0 + 30.0 * f
		var r1 := r0 + 26.0 * (1.0 - f) * lens(along)
		var a := _point(angle, r0)
		var b := _point(angle, r1)
		if a.distance_to(b) < 0.6: continue
		var across := (b - a).normalized().orthogonal() * 0.5
		_canvas.draw_colored_polygon(PackedVector2Array([a - across, b - across, b + across, a + across]), palette[1] if f < 0.5 else palette[2])

func _draw_star() -> void:
	var open := ease_swing(age / duration)
	var f := _fade_fraction()
	var c := center
	c.x *= facing
	c /= pixel_size
	var rays := maxi(burst_spikes, 4)
	for i in rays:
		var long_ray := i % 2 == 0
		var dir := Vector2.from_angle(spark_dir + TAU * i / rays)
		dir.x *= facing
		var length := radius * open * (1.0 if long_ray else 0.5) * (1.0 - f * 0.6) / pixel_size
		var base := width * (1.0 - f) * (0.6 if long_ray else 0.4) / pixel_size
		if length < 0.6 or base < 0.2: continue
		var side := dir.orthogonal() * maxf(base, 0.5)
		var colour: Color = (palette[0] if long_ray else palette[1]) if f < 0.4 else palette[2]
		_canvas.draw_colored_polygon(PackedVector2Array([c + side, c + dir * length, c - side]), colour)
	# White core, then a thin ring that opens past the rays.
	var core := width * 0.9 * (1.0 - f) / pixel_size
	if core >= 0.6: _canvas.draw_circle(c, core, palette[0])
	# A thin ring just inside the long rays, gone early in the fade.
	var ring := radius * 0.7 * open * (0.9 + f * 0.5) / pixel_size
	if f < 0.4: _canvas.draw_arc(c, ring, 0.0, TAU, 24, palette[1], 1.0)

## Offline ground attack body: a fractured salt crown, swept shock lip and eroding chips.
## Geometry stays inside the same authored footprint; no contact stars or flash overlays.
func _draw_quake() -> void:
	var opened := ease_swing(age / duration)
	var f := clampf((age-duration)/tail,0,1)
	if f>=1: return
	var r := radius*opened
	if r<1.0: return
	var strength := pow(1.0-f,0.8)
	var impact_age := maxf(0.0,age-duration)
	var struck := age >= duration
	# First the crust compresses, then the same slabs are launched and fall heavily.
	# The hit and footprint are unchanged; these are material motions after contact.
	var compression := 0.45+0.55*ease_swing(impact_age/0.035) if struck else 0.22
	var erosion := 1.0-clampf((impact_age-0.12)/0.12,0,1)
	var main: Color = palette[2]
	var bright: Color = palette[1]
	var dark: Color = palette[3]
	main.a = strength*0.82
	bright.a = strength
	dark.a = strength*0.65
	# A subdued ground shadow gives the lifting plates a solid base.
	var shadow := PackedVector2Array()
	for i in 48:
		var angle := TAU*i/48.0
		shadow.append(Vector2(cos(angle)*r,sin(angle)*r*squash)/pixel_size)
	var shadow_color: Color = palette[3]
	shadow_color.a = strength*(0.22+0.24*exp(-impact_age/0.045))
	if r>1: _canvas.draw_colored_polygon(shadow,shadow_color)
	# Halite reads as cubic cleavage and chalk-white salt crust, not pointed quartz.
	# Reuse the existing footprint and opening envelope; only the material changes.
	var salt_top := Color("edf4ef").lerp(palette[1],0.25)
	var salt_side := Color("b9cbc5").lerp(palette[2],0.25)
	var salt_shade := Color("758c88").lerp(palette[3],0.28)
	for i in 13:
		var a := TAU*float((i+6)%13)/13.0+sin(float(i)*7.3)*0.06
		var variation := 0.5+0.5*sin(float(i)*13.17+2.4)
		var reach := r*(0.54+variation*0.24)
		var base := Vector2(cos(a)*reach,sin(a)*reach*squash)
		var size := (7.0+variation*10.0)*opened*erosion*(radius/140.0)
		var height := (7.0+variation*16.0)*opened*erosion*compression*(radius/140.0)
		var flight := maxf(0.0,(180.0+variation*90.0)*impact_age-1700.0*impact_age*impact_age)
		base.y -= flight*(radius/140.0)
		if struck and impact_age>0.15: base.y += sin((impact_age-0.15)*42.0)*exp(-(impact_age-0.15)*32.0)*1.5
		_salt_cube(base,size,height,salt_top,salt_side,salt_shade,strength)
		if i%3==0:
			_salt_cube(base+Vector2(size*0.36,-height),size*0.55,height*0.38,salt_top,salt_side,salt_shade,strength)
	# Hairline square cleavage marks and a sparse white salt film remain between blocks.
	for i in 9:
		var a := float(i)*2.39996
		var base := Vector2(cos(a)*r*0.43,sin(a)*r*squash*0.43)/pixel_size
		var length := r*(0.16+float(i%3)*0.025)/pixel_size
		var color := salt_top
		color.a = strength*0.65
		_canvas.draw_polyline(PackedVector2Array([base,base+Vector2(length,0),base+Vector2(length,length*0.18)]),color,1.0)
	# Swept front shock lip, with gaps and tapered bright ends.
	for i in 36:
		var a := TAU*i/36.0
		var b := a+TAU/36.0*0.86
		var impulse := exp(-impact_age/0.055) if struck else 0.25
		var width := (4.0+6.0*maxf(0,sin(a)))*strength+12.0*impulse
		_band(a,b,maxf(0,r-width-3.0),maxf(0,r-width),maxf(0,r-width-3.0),maxf(0,r-width),dark)
		_band(a,b,maxf(0,r-width),r,maxf(0,r-width*0.65),r,bright if i%4 else main)
	# Cubic salt fragments and fine dry grains replace sharp mineral splinters.
	for i in 22:
		var a := float(i)*2.39996
		var drift := maxf(0,age-duration)
		var fraction := 0.25+float(i%7)/10.0
		var pos := Vector2(cos(a),sin(a)*squash)*r*fraction
		pos.y -= maxf(0.0,(210.0+float(i%5)*25.0)*drift-1900.0*drift*drift)
		var size := (1.5+float(i%3))*strength if struck else 0.0
		if size<0.9: continue
		_salt_cube(pos,size,size*1.2,salt_top,salt_side,salt_shade,strength)
	for i in 34:
		var a := float(i)*2.39996+0.37
		var fraction := 0.25+float(i%9)*0.075
		var pos := Vector2(cos(a)*r*fraction,sin(a)*r*squash*fraction)
		var flight := maxf(0.0,(120.0+float(i%6)*18.0)*impact_age-1550.0*impact_age*impact_age)
		pos.y -= flight
		var color := salt_top
		color.a = strength*0.72 if struck else 0.0
		_canvas.draw_rect(Rect2(pos/pixel_size,Vector2.ONE),color)

func _salt_cube(base: Vector2, half_width: float, height: float, top_color: Color, side_color: Color, shade_color: Color, alpha: float) -> void:
	if half_width<0.7 or height<0.7: return
	var top := (base-Vector2(0,height))/pixel_size
	var left := top+Vector2(-half_width,0)/pixel_size
	var right := top+Vector2(half_width,0)/pixel_size
	var back := top+Vector2(0,-half_width*0.38)/pixel_size
	var front := top+Vector2(0,half_width*0.38)/pixel_size
	var down := Vector2(0,height)/pixel_size
	top_color.a = alpha*0.94
	side_color.a = alpha*0.90
	shade_color.a = alpha*0.82
	_canvas.draw_colored_polygon(PackedVector2Array([left,back,right,front]),top_color)
	_canvas.draw_colored_polygon(PackedVector2Array([left,front,front+down,left+down]),side_color)
	_canvas.draw_colored_polygon(PackedVector2Array([front,right,right+down,front+down]),shade_color)
	var edge := Color("f8fbf3",alpha)
	_canvas.draw_polyline(PackedVector2Array([left,back,right]),edge,1.0)

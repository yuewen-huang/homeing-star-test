extends Node2D
## Offline-only source for bake_lan_heavy_charge.gd; never loaded by the game.
## The offline baker advances the original action clock; it creates no damage/contact burst.

const HALO_RADIUS := 64.0
const FULL_RADIUS := 34.0
const RELEASE_FADE := 0.14
var halo: PixelSlash
var parts: Array[PixelSlash] = []
var charging := false
var full_cue_played := false
var clock := 0.0
var gather_remaining := 0.0


func _ready() -> void:
	name = "HeavyChargeVisual"
	z_index = 1


func advance(delta: float, active: bool, ratio: float, _facing: float) -> void:
	if delta <= 0.0: return
	if active and not charging:
		_begin()
	elif not active and charging:
		_release()
	charging = active
	clock += delta
	if active:
		var charge := clampf(ratio, 0.0, 1.0)
		var pulse := sin(clock * 9.0) * 0.5 + 0.5
		halo.radius = lerpf(HALO_RADIUS, FULL_RADIUS, charge) + pulse * charge * 2.0
		halo.modulate.a = lerpf(0.45, 0.9, charge)
		gather_remaining -= delta
		if gather_remaining <= 0.0:
			_gather(charge)
			gather_remaining = 0.19 if charge < 1.0 else 0.32
		if charge >= 1.0 and not full_cue_played:
			full_cue_played = true
			_add({"shape": &"star", "radius": 27.0, "width": 5.0,
				"burst_spikes": 4, "spark_dir": PI / 4.0,
				"duration": 0.04, "hold": 0.06, "fade": 0.16})
	for part: PixelSlash in parts.duplicate():
		part.advance(delta)
		if part.is_done():
			parts.erase(part)
			part.queue_free()


func _begin() -> void:
	# A new windup replaces any fading ring from the previous one.
	if is_instance_valid(halo):
		parts.erase(halo)
		halo.queue_free()
	clock = 0.0
	full_cue_played = false
	gather_remaining = 0.0
	halo = _add({"shape": &"burst", "radius": HALO_RADIUS, "width": 6.0,
		"squash": 0.72, "burst_spikes": 0, "duration": 0.08, "tail": INF})
	# Keep the ring blue, with the same pixel grid and palette as Lan's slashes.
	halo.palette = halo.palette.duplicate()
	halo.palette[0] = halo.palette[2]


func _release() -> void:
	if is_instance_valid(halo):
		halo.duration = 0.001
		halo.tail = RELEASE_FADE
		halo.age = halo.duration
	# Stop incoming particles immediately; only the halo has a short release tail.
	for part: PixelSlash in parts.duplicate():
		if part == halo: continue
		parts.erase(part)
		part.queue_free()


func _gather(ratio: float) -> void:
	_add({"shape": &"sparks", "spark_count": 7, "spark_spread": PI,
		"spark_speed": Vector2(150, 230), "spark_life": Vector2(0.23, 0.31),
		"spark_gravity": 0.0, "spark_converge": true, "spark_streak": false,
		"spark_seed": 19 + int(clock * 100.0)}).modulate.a = lerpf(0.55, 0.95, ratio)


func _add(preset: Dictionary) -> PixelSlash:
	preset["palette"] = &"normal"
	var part := PixelSlash.new().configure(preset)
	add_child(part)
	parts.append(part)
	return part

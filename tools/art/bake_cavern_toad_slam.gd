extends SceneTree
## Rebuild the nearest-filtered water splash used by the A25 slam.
## godot --headless --path homeing-star-game --script <absolute path to this script>

const OUTPUT := "res://assets/levels/chapter_2_underwater/cavern/boss/bronze_toad/"
const SPLASH_CELL := Vector2i(160, 42)
const SPLASH_ORIGIN := Vector2(80, 38)
const WATER := Color("386a7b")
const FOAM := Color("c9ece4")
const RIM := Color("78b9c1")

# Each profile traces the lower edge outwards, then curls back along the crest.
const SQUEEZE := [Vector2(0,-1), Vector2(18,-1), Vector2(43,-1), Vector2(47,-3),
	Vector2(32,-7), Vector2(26,-9), Vector2(22,-7), Vector2(15,-10), Vector2(6,-6)]
const CREST := [Vector2(4,-1), Vector2(25,-1), Vector2(56,-3), Vector2(67,-12),
	Vector2(64,-27), Vector2(55,-34), Vector2(59,-22), Vector2(34,-14), Vector2(14,-5)]
const COLLAPSE := [Vector2(24,-1), Vector2(41,-1), Vector2(70,-2), Vector2(78,-5),
	Vector2(69,-12), Vector2(57,-17), Vector2(62,-9), Vector2(47,-6), Vector2(32,-2)]

func _initialize() -> void:
	var splash := Image.create_empty(SPLASH_CELL.x * 12, SPLASH_CELL.y, false, Image.FORMAT_RGBA8)
	for frame in 12:
		var at := SPLASH_ORIGIN + Vector2(frame * SPLASH_CELL.x, 0)
		_splash(splash, at, frame / 30.0, -1.0)
		_splash(splash, at, frame / 30.0, 1.0)
	var status := splash.save_png(OUTPUT + "slam_splash_160x42_12f.png")
	quit(status)


func _splash(sheet: Image, at: Vector2, age: float, side: float) -> void:
	var spread := 0.92 if side < 0.0 else 1.0
	var height := 0.91 if side < 0.0 else 0.80
	if age < 0.21:
		var opening := age < 0.067
		var progress := smoothstep(0.0, 0.067, age) if opening else smoothstep(0.067, 0.21, age)
		var start := SQUEEZE if opening else CREST
		var end := CREST if opening else COLLAPSE
		var profile := PackedVector2Array()
		for i in start.size():
			profile.append(at + (start[i] as Vector2).lerp(end[i], progress) * Vector2(side * spread, height))
		var opacity := 1.0 - smoothstep(0.095, 0.21, age)
		_fill(sheet, profile, Color(WATER, opacity))
		_fill(sheet, PackedVector2Array([profile[3], profile[4], profile[5], profile[6],
			profile[7], profile[7].lerp(profile[2], 0.45), profile[3].lerp(profile[2], 0.55)]), Color(RIM, opacity))
		_stroke(sheet, profile[5], profile[4].lerp(profile[3], 0.48), 0.65, Color(FOAM, opacity))
		_stroke(sheet, profile[6].lerp(profile[7], 0.20), profile[7], 0.66, Color(FOAM, opacity * 0.8))
	for i in 16:
		var launch := (i % 5) * 0.015
		var flight := age - launch
		if flight < 0.0: continue
		var speed := Vector2(107 + i * 2 + (i * 53 % 71), -63.0 - (i * 37 % 154))
		var from := Vector2(14.0 + (i * 7 % 23), -1.0 - (i % 4))
		var offset := from + speed * flight + Vector2(0, 560.0 * flight * flight)
		if offset.y >= -1.0 or offset.x >= 79.0: continue
		var point := at + offset * Vector2(side * spread, height)
		var motion := (speed + Vector2(0, 1120 * flight)).normalized() * Vector2(side, 1)
		var alpha := 1.0 - smoothstep(0.13, 0.29, flight)
		var radius := 0.65 + (i * 19 % 7) * 0.13
		_stroke(sheet, point - motion * (2.5 + i % 3), point, radius, Color(RIM, alpha))
		_stroke(sheet, point - motion, point, 0.58, Color(FOAM, alpha))
	if age > 0.10:
		var t := smoothstep(0.10, 0.36, age)
		for i in 4:
			var edge := at + Vector2(side * (16.0 + 13.0 * i + t * (19.0 + i)), -1.0 - (i % 2))
			_stroke(sheet, edge - Vector2(side * (7 + i), 0), edge, 0.55, Color(RIM, (1.0 - t) * 0.77))


func _stroke(sheet: Image, start: Vector2, end: Vector2, radius: float, ink: Color) -> void:
	var normal := start.direction_to(end).orthogonal() * radius
	_fill(sheet, PackedVector2Array([start + normal, end + normal, end - normal, start - normal]), ink)


func _fill(sheet: Image, points: PackedVector2Array, ink: Color) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	for y in range(maxi(0, floori(bounds.position.y)), mini(sheet.get_height(), ceili(bounds.end.y))):
		for x in range(maxi(0, floori(bounds.position.x)), mini(sheet.get_width(), ceili(bounds.end.x))):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				sheet.set_pixel(x, y, ink if ink.a >= 1.0 else sheet.get_pixel(x, y).blend(ink))

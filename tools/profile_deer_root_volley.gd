extends SceneTree

class TimedVolley extends DeerRootVolley:
	var draw_us: Array[int] = []
	var ellipse_us := 0
	var ellipse_calls := 0
	func _draw() -> void:
		var started := Time.get_ticks_usec()
		super._draw()
		draw_us.append(Time.get_ticks_usec() - started)
	func _draw_pixel_ellipse(center: Vector2, rx: float, ry: float, color: Color, filled: bool) -> void:
		var started := Time.get_ticks_usec()
		super._draw_pixel_ellipse(center, rx, ry, color, filled)
		ellipse_us += Time.get_ticks_usec() - started
		ellipse_calls += 1

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = Vector2(1280, 360)
	camera.make_current()
	var volley := TimedVolley.new()
	volley.no_player_damage = true
	volley.ground_y = 555
	root.add_child(volley)
	var art := DeerRootArt.new()
	art.rng.seed = 24
	var started := Time.get_ticks_usec()
	for i in 18:
		volley.add_root(100 + i * 131.1, 0, 1.0, art.choose("high"), i % 2 == 0)
	print("BUILD_US=", Time.get_ticks_usec() - started)
	for i in 108:
		volley.step(1.0 / 60)
		await process_frame
	var samples := volley.draw_us
	samples.sort()
	var total := 0
	for value in samples: total += value
	if not samples.is_empty():
		print("DRAW samples=%d avg_us=%d p95_us=%d max_us=%d ellipse_us=%d ellipse_calls=%d" % [samples.size(), total / samples.size(), samples[int(samples.size() * 0.95)], samples.back(), volley.ellipse_us, volley.ellipse_calls])
	else: print("NO DRAW SAMPLES")
	volley.queue_free()
	await process_frame
	quit()

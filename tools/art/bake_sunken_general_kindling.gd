extends SceneTree
## Run in Combat VFX Studio and pass the game FX folder after --.

const SOURCE := "res://combos/sunken_general_kindling/combo.json"
const Fire = preload("res://vfx/kindling_fire.gd")
const COLUMNS := 8
const BODY_COUNT := 64
const DRAW_COUNT := 40
const EDGE_COUNT := 32
const BURST_COUNT := 24


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	var events := ComboStage.load_timeline(SOURCE)
	if args.size() != 1 or events.size() != 1 or events[0].get("stroke") != "kindling_fire":
		push_error("Expected the saved kindling event and an output folder")
		quit(1)
		return
	var fire := Fire.new()
	fire.spec = Fire.normalized(events[0])
	var duration := float(fire.spec.duration)
	var burst_at := float(fire.spec.burst_at)
	var gather_at := float(fire.spec.gather_at)
	var gather := float(fire.spec.gather)
	if not is_equal_approx(duration, 3.25) or not is_equal_approx(gather_at, 0.8) \
			or not is_equal_approx(gather, 1.4) or not is_equal_approx(burst_at, 2.42):
		push_error("The saved stance and eruption beats must match the General's action clock")
		fire.free()
		quit(1)
		return
	var error := await _render(fire, 0, Fire.BODY_CELL, BODY_COUNT, 0.0, gather_at + gather, args[0].path_join("kindling_body_back_144x136_64f.png"))
	if error == OK:
		error = await _render(fire, 3, Fire.BODY_CELL, BODY_COUNT, 0.0, gather_at + gather, args[0].path_join("kindling_body_front_144x136_64f.png"))
	if error == OK:
		error = await _render(fire, 4, Fire.DRAW_CELL, DRAW_COUNT, gather_at, gather, args[0].path_join("kindling_draw_224x160_40f.png"))
	if error == OK:
		error = await _render(fire, 2, Fire.BURST_CELL, BURST_COUNT, burst_at, duration - burst_at, args[0].path_join("kindling_burst_256x192_24f.png"))
	if error == OK:
		error = await _render(fire, 1, Fire.EDGE_CELL, EDGE_COUNT, 7.0, 1.0, args[0].path_join("kindling_edge_112x64_32f.png"))
	if error == OK:
		error = await _render(fire, 5, Fire.SHAFT_CELL, EDGE_COUNT, 7.0, 1.0, args[0].path_join("kindling_shaft_160x40_32f.png"))
	fire.free()
	quit(error)


func _render(fire: Fire, part: int, cell: Vector2i, count: int, start: float, duration: float, output: String) -> Error:
	var view := SubViewport.new()
	view.size = cell
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(fire.make_layer(part, Rect2(Vector2.ZERO, Vector2(cell))))
	var atlas := Image.create_empty(cell.x * COLUMNS, cell.y * ceili(float(count) / COLUMNS), false, Image.FORMAT_RGBA8)
	var looping := part == 1 or part == 5
	var enabled := part != 5 or float(fire.spec.shaft_strength) > 0.0
	for index in count:
		var intervals := count if looping else count - 1
		var at := start + float(index) * duration / intervals
		fire.advance(at - fire.age)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		var ink := frame.get_used_rect()
		if (enabled and index == count / 2 and not ink.has_area()) or (not looping and index == count - 1 and ink.has_area()):
			push_error("Unexpected frame %d in %s" % [index, output])
			return ERR_INVALID_DATA
		for y in range(ink.position.y, ink.end.y):
			for x in range(ink.position.x, ink.end.x):
				var pixel := frame.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.a < 1.0:
					frame.set_pixel(x, y, Color(pixel.r / pixel.a, pixel.g / pixel.a, pixel.b / pixel.a, pixel.a))
		@warning_ignore("integer_division")
		var tile := Vector2i(index % COLUMNS, index / COLUMNS)
		atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), tile * cell)
	view.queue_free()
	fire._materials.clear()
	return atlas.save_png(output)

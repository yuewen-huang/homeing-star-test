extends SceneTree
## Run in Combat VFX Studio and pass the output folder after --.

const SOURCE := "res://combos/sunken_general_red_dash/"
const Dash = preload("res://vfx/soul_dash.gd")
const FlowStage = preload("res://vfx/flow_stage.gd")
const COLUMNS := 6
const ROWS := 4
const LENGTH := 0.90


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]):
		push_error("Pass the output folder after --")
		quit(1)
		return
	ComboStyle.load_file(SOURCE + "style.json")
	var events := ComboStage.load_timeline(SOURCE + "combo.json")
	if events.size() != 2 or not events.all(_matches_game_timing):
		push_error("The red dash needs the game's 420 px reference run, 0.66 s travel and a tail under 0.90 s")
		quit(1)
		return
	var wake: Array = events.filter(func(e: Dictionary) -> bool: return e.layer == "wake")
	var head: Array = events.filter(func(e: Dictionary) -> bool: return e.layer == "head")
	if wake.size() != 1 or head.size() != 1 or not is_equal_approx(float(wake[0].t), float(head[0].t)):
		push_error("The head and wake must share the release frame")
		quit(1)
		return
	var error := await _render(wake[0], Dash.ORIGIN, args[0].path_join("soul_dash_288x192_24f.png"))
	if error == OK:
		error = await _render(head[0], Dash.HEAD_ORIGIN, args[0].path_join("soul_dash_head_288x192_24f.png"))
	quit(error)


func _matches_game_timing(event: Dictionary) -> bool:
	return (event.get("stroke") == "soul_dash"
		and is_equal_approx(float(event.distance), Dash.DISTANCE)
		and is_equal_approx(float(event.duration), Dash.TRAVEL)
		and float(event.duration) + float(event.fade) < LENGTH)


func _render(event: Dictionary, origin: Vector2, output: String) -> Error:
	var view := SubViewport.new()
	view.size = Vector2i(Vector2(Dash.CELL) * Dash.PIXEL)
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var stage := FlowStage.new()
	view.add_child(stage)
	stage.set_process(false)
	stage._camera.enabled = false
	stage.position = origin - Vector2(stage.ATTACKER_START.x, stage.GROUND_Y)
	stage.self_modulate.a = 0.0
	stage.TIMELINE = [event]
	stage.play()
	stage.attacker.hide()
	stage.target.hide()
	stage.overlay.hide()

	var release := float(event.t)
	var count := COLUMNS * ROWS
	var atlas := Image.create_empty(Dash.CELL.x * COLUMNS, Dash.CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	for index in count:
		var elapsed := (index + 0.5) * LENGTH / count
		while stage.clock < release + elapsed - 0.000001:
			stage.advance(minf(1.0 / 240.0, release + elapsed - stage.clock))
		if event.layer == "head":
			# The game attaches the head to the moving boss. Bake in its local space.
			stage.position.x = origin.x - stage.ATTACKER_START.x - Dash.DISTANCE * ease(minf(elapsed / Dash.TRAVEL, 1.0), Dash.EASE)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		frame.resize(Dash.CELL.x, Dash.CELL.y, Image.INTERPOLATE_NEAREST)
		var ink := frame.get_used_rect()
		if (index == 8 and not ink.has_area()) or (index == count - 1 and ink.has_area()):
			push_error("Unexpected visibility in %s at cell %d" % [output, index])
			return ERR_INVALID_DATA
		if ink.has_area() and (ink.position.x == 0 or ink.position.y == 0 or ink.end.x == Dash.CELL.x or ink.end.y == Dash.CELL.y):
			push_error("Frame %d reaches the atlas edge in %s: %s" % [index, output, ink])
			return ERR_INVALID_DATA
		for y in range(ink.position.y, ink.end.y):
			for x in range(ink.position.x, ink.end.x):
				var pixel := frame.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.a < 1.0:
					frame.set_pixel(x, y, Color(pixel.r / pixel.a, pixel.g / pixel.a, pixel.b / pixel.a, pixel.a))
		@warning_ignore("integer_division")
		var tile := Vector2i(index % COLUMNS, index / COLUMNS)
		atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, Dash.CELL), tile * Dash.CELL)
	view.queue_free()
	return atlas.save_png(output)

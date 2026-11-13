extends SceneTree
## Run in Combat VFX Studio with the output PNG path after --.

const SOURCE := "res://combos/sunken_general_uppercut/"
const FlowStage = preload("res://vfx/flow_stage.gd")
const CELL := Vector2i(480, 224)
const ORIGIN := Vector2(520.0, 490.0)
const COLUMNS := 6
const ROWS := 6
# Keep the previous sampling interval and give the longer ground dust room to finish.
const LENGTH := 0.9375


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the output PNG path after --")
		quit(1)
		return
	ComboStyle.load_file(SOURCE + "style.json")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(Vector2(CELL) * ComboStyle.pixel)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Render the same flow stage that plays in Studio. Keep only the effect layers.
	var stage := FlowStage.new()
	stage.combo_file = SOURCE + "combo.json"
	viewport.add_child(stage)
	stage.set_process(false)
	stage._camera.enabled = false
	stage.position = ORIGIN - Vector2(stage.ATTACKER_START.x, stage.GROUND_Y)
	stage.self_modulate.a = 0.0
	stage.play()
	stage.attacker.hide()
	stage.target.hide()
	stage.overlay.hide()
	if stage.TIMELINE.is_empty():
		push_error("Studio has no uppercut events to bake")
		quit(1)
		return
	var release := float(stage.TIMELINE[0].t)
	var count := COLUMNS * ROWS
	var atlas := Image.create_empty(CELL.x * COLUMNS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	for index in count:
		var time := release + (index + 0.5) * LENGTH / count
		while stage.clock < time - 0.000001:
			stage.advance(minf(1.0 / 240.0, time - stage.clock))
		# Ground decals linger after the moving dust. Blend them out over the final
		# few samples so the floor doesn't pop when the baked effect is freed.
		stage.fx.modulate.a = 1.0 - smoothstep(LENGTH - 0.12, LENGTH - 0.02, time - release)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := viewport.get_texture().get_image()
		frame.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
		var ink := frame.get_used_rect()
		if (index == 0 and ink.size == Vector2i.ZERO) or (index == count - 1 and ink.size != Vector2i.ZERO):
			push_error("Unexpected visibility at uppercut cell %d" % index)
			quit(1)
			return
		if ink.has_area() and (ink.position.x == 0 or ink.position.y == 0 or ink.end.x == CELL.x or ink.end.y == CELL.y):
			push_error("Uppercut cell %d reaches the bake boundary: %s" % [index, ink])
			quit(1)
			return
		for y in range(ink.position.y, ink.end.y):
			for x in range(ink.position.x, ink.end.x):
				var pixel := frame.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.a < 1.0:
					frame.set_pixel(x, y, Color(pixel.r / pixel.a, pixel.g / pixel.a, pixel.b / pixel.a, pixel.a))
		@warning_ignore("integer_division")
		var tile := Vector2i(index % COLUMNS, index / COLUMNS)
		atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, CELL), tile * CELL)
	quit(atlas.save_png(args[0]))

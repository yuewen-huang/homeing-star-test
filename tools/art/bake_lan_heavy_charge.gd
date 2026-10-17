extends SceneTree
## Offline baker. Render with --fixed-fps 60; outputs a transparent 16-column sheet.
const SOURCE = preload("./lan_heavy_charge_source.gd")
const FRAME_SIZE := 64
const COLUMNS := 16
const CHARGE_FRAMES := 54
const FULL_START_FRAMES := 16
const LOOP_FRAMES := 42
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Pass the output PNG path after --")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(FRAME_SIZE, FRAME_SIZE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node2D.new()
	world.position = Vector2.ONE * FRAME_SIZE * 0.5
	world.scale = Vector2.ONE / 3.0
	viewport.add_child(world)
	var effect = SOURCE.new()
	world.add_child(effect)
	var count := CHARGE_FRAMES + FULL_START_FRAMES + LOOP_FRAMES
	var sheet := Image.create(FRAME_SIZE * COLUMNS, FRAME_SIZE * ceili(float(count) / COLUMNS), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for index in count:
		var ratio := minf(1.0, float(index) / CHARGE_FRAMES)
		effect.advance(1.0 / 60.0, true, ratio, 1.0)
		# PixelSlash draws into nested low-resolution viewports. Two render passes
		# settle those textures before sampling the outer transparent viewport.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var frame := viewport.get_texture().get_image()
		sheet.blit_rect(frame, Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE), Vector2i(index % COLUMNS, index / COLUMNS) * FRAME_SIZE)
		if index % 24 == 0: print("Baking charge: %d / %d" % [index, count])
	# Transparent viewport captures contain premultiplied RGB. PNG sprites use
	# straight alpha; undo it once here so playback does not darken translucent rings.
	for y in sheet.get_height():
		for x in sheet.get_width():
			var colour := sheet.get_pixel(x, y)
			if colour.a > 0.0:
				sheet.set_pixel(x, y, Color(minf(1.0, colour.r / colour.a), minf(1.0, colour.g / colour.a), minf(1.0, colour.b / colour.a), colour.a))
	var result := sheet.save_png(args[0])
	assert(result == OK, "Could not write baked charge sheet")
	print("BAKED %d frames, %s; %s" % [count, sheet.get_size(), args[0]])
	viewport.free()
	quit()

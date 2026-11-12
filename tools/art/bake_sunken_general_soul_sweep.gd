extends SceneTree
## Run in Combat VFX Studio. Pass an output PNG or --moves <game FX folder> after --.

const SWEEP = preload("res://combos/sunken_general_soul_sweep/soul_sweep.gdshader")
const MOVES = preload("res://combos/sunken_general_soul_sweep/soul_moves.gdshader")
const MOVE_NAMES := ["reverse", "uppercut", "dash", "chop", "chop_wave"]


func _initialize() -> void:
	call_deferred("bake")


func bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 1:
		quit(await _render_atlas(SWEEP, Vector2i(480, 256), 7, 42, args[0]))
	elif args.size() == 2 and args[0] == "--moves":
		for index in MOVE_NAMES.size():
			var output := args[1].path_join("soul_%s_288x192_24f.png" % MOVE_NAMES[index])
			var error := await _render_atlas(MOVES, Vector2i(288, 192), 6, 24, output, index)
			if error != OK:
				quit(error)
				return
		quit(0)
	else:
		push_error("Pass the output PNG, or --moves followed by the output folder")
		quit(1)


func _render_atlas(shader: Shader, cell: Vector2i, columns: int, count: int, output: String,
		move_kind := -1) -> Error:
	var view := SubViewport.new()
	view.size = cell
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var quad := ColorRect.new()
	quad.size = cell
	var material := ShaderMaterial.new()
	material.shader = shader
	quad.material = material
	view.add_child(quad)
	var atlas := Image.create_empty(cell.x * columns, cell.y * ceili(float(count) / columns), false, Image.FORMAT_RGBA8)
	if move_kind >= 0:
		material.set_shader_parameter("move_kind", move_kind)
	for index in count:
		if move_kind < 0:
			material.set_shader_parameter("opening", smoothstep(0.0, 12.0, float(index)))
			material.set_shader_parameter("phase", fposmod(float(index - 12), 30.0) / 30.0)
		else:
			material.set_shader_parameter("progress", float(index) / count)
			material.set_shader_parameter("phase", float(index) / count)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		if frame.is_invisible():
			push_error("Empty rendered cell %d in %s" % [index, output])
			view.queue_free()
			return ERR_INVALID_DATA
		# A transparent viewport returns premultiplied pixels. Save straight alpha.
		for y in cell.y:
			for x in cell.x:
				var pixel := frame.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.a < 1.0:
					frame.set_pixel(x, y, Color(pixel.r / pixel.a, pixel.g / pixel.a, pixel.b / pixel.a, pixel.a))
		@warning_ignore("integer_division")
		var tile := Vector2i(index % columns, index / columns)
		atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), tile * cell)
	view.queue_free()
	var error := atlas.save_png(output)
	print("%s: %d rendered cells, save result %d" % [output.get_file(), count, error])
	return error

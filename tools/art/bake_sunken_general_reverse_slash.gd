extends SceneTree
## Run against Combat VFX Studio with the output PNG path after --.

const SOURCE := "res://combos/sunken_general_reverse_slash"
const CELL := Vector2i(288, 192)
const ORIGIN := Vector2(385.0, 429.0)
const COLUMNS := 6
const FRAMES := 24
const PIXEL := 2.75
const LENGTH := 0.60
const Ribbon = preload("res://vfx/trajectory_ribbon.gd")
const Quake = preload("res://vfx/quake_effect.gd")


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the output PNG path after --")
		quit(1)
		return
	var combo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE.path_join("combo.json")))
	ComboStyle.load_file(SOURCE.path_join("style.json"))
	var blade: Dictionary = combo.events.filter(func(e: Dictionary) -> bool: return e.do == "slash")[0]
	var dust: Dictionary = combo.events.filter(func(e: Dictionary) -> bool: return e.do == "quake")[0]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(Vector2(CELL) * PIXEL)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Both events use the Studio renderers. The bake maps the editor floor point
	# (640, 520) to the boss origin and keeps the authored smoke and blade in front.
	var fog := Quake.new().configure(dust)
	fog.position += ORIGIN - Vector2(640.0, 520.0)
	viewport.add_child(fog)
	fog.hide()
	var slash := Ribbon.new()
	slash.configure({
		"radius": float(blade.radius), "squash": float(blade.squash),
		"tilt": deg_to_rad(float(blade.get("tilt", 0.0))),
		"start_angle": deg_to_rad(float(blade.from)), "end_angle": deg_to_rad(float(blade.to)),
		"width": float(blade.width), "duration": float(blade.duration), "tail": float(blade.tail),
		"hilt_travel": 0.0, "swell": 0.0, "echo": false, "pixel": PIXEL,
		"palette": PixelSlash.palette_of(StringName(blade.palette)),
	})
	# Keep the downward bow of the cutting edge in the standing target's silhouette.
	slash.position = ORIGIN + Vector2(0.0, -198.0)
	slash.z_index = 3
	viewport.add_child(slash)

	var fog_delay := float(dust.t) - float(blade.t)
	@warning_ignore("integer_division")
	var atlas := Image.create_empty(CELL.x * COLUMNS, CELL.y * (FRAMES / COLUMNS), false, Image.FORMAT_RGBA8)
	for index in FRAMES:
		var time := (index + 0.5) * LENGTH / FRAMES
		slash.advance(time - slash.age)
		if time > fog_delay:
			fog.show()
			fog.advance(time - fog_delay - fog.age)
			fog.modulate.a = 1.0 - smoothstep(0.38, LENGTH - 0.015, time)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := viewport.get_texture().get_image()
		frame.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
		var ink := frame.get_used_rect()
		for y in range(ink.position.y, ink.end.y):
			for x in range(ink.position.x, ink.end.x):
				var rgba := frame.get_pixel(x, y)
				if rgba.a > 0.0 and rgba.a < 1.0:
					frame.set_pixel(x, y, Color(rgba.r / rgba.a, rgba.g / rgba.a, rgba.b / rgba.a, rgba.a))
		@warning_ignore("integer_division")
		var tile := Vector2i(index % COLUMNS, index / COLUMNS)
		atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, CELL), tile * CELL)
	if atlas.is_invisible():
		push_error("The Studio render did not produce a reverse slash")
		quit(1)
		return
	quit(atlas.save_png(args[0]))

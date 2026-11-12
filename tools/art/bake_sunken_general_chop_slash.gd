extends SceneTree
## Run in Combat VFX Studio with the output PNG path after --.

const SOURCE := "res://combos/sunken_general_chop_slash"
const CELL := Vector2i(288, 192)
const BODY_ORIGIN := Vector2i(96, 156)
const COLUMNS := 6
const FRAMES := 24
const Ribbon = preload("res://vfx/trajectory_ribbon.gd")


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the output PNG path after --")
		quit(1)
		return
	var combo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE.path_join("combo.json")))
	var event: Dictionary = combo.events[0]
	ComboStyle.load_file(SOURCE.path_join("style.json"))
	var slash := Ribbon.new()
	slash.configure({
		"radius": float(event.radius), "squash": float(event.squash),
		"tilt": deg_to_rad(float(event.get("tilt", 0.0))),
		"start_angle": deg_to_rad(float(event.from)), "end_angle": deg_to_rad(float(event.to)),
		"width": float(event.width), "duration": float(event.duration), "tail": float(event.tail),
		"hilt_travel": 0.0, "swell": 0.0, "echo": false, "pixel": ComboStyle.pixel,
		"palette": PixelSlash.palette_of(StringName(event.palette)),
	})
	root.add_child(slash)
	var viewport := slash.blade.get_parent() as SubViewport
	@warning_ignore("integer_division")
	var atlas := Image.create_empty(CELL.x * COLUMNS, CELL.y * (FRAMES / COLUMNS), false, Image.FORMAT_RGBA8)
	var step := (slash.duration + slash.tail) / FRAMES
	for index in FRAMES:
		slash.advance(step)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := viewport.get_texture().get_image()
		var ink := frame.get_used_rect()
		if ink.has_area():
			var shoulder := BODY_ORIGIN - Vector2i(0, 38)
			var at := shoulder + ink.position - Vector2i(slash.blade.position)
			if not Rect2i(Vector2i.ZERO, CELL).encloses(Rect2i(at, ink.size)):
				push_error("The vertical cut exceeds its sprite cell")
				quit(1)
				return
			@warning_ignore("integer_division")
			var tile := Vector2i(index % COLUMNS, index / COLUMNS)
			atlas.blit_rect(frame, ink, tile * CELL + at)
	if atlas.is_invisible():
		push_error("The Studio renderer did not produce a slash")
		quit(1)
		return
	quit(atlas.save_png(args[0]))

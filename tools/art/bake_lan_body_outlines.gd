extends SceneTree
## Run headless against the game project after replacing Lan's body sheets.
## Pass the output JSON path after --. Coordinates are pixels within each atlas cell.
const BODY_COLORS := ["f5c477", "f8d083", "f4c477", "fee6a5", "da9a51", "27484c",
		"315b60", "20383d", "192b30", "79482f", "78482e", "482e26", "492f26"]
var palette := {}
var sheets := {}

func _initialize() -> void:
	call_deferred("bake")

func bake() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the destination JSON path after --")
		quit(1)
		return
	for hex: String in BODY_COLORS:
		palette[Color(hex).to_rgba32()] = true
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	player.world_min_x = -1000
	player.world_max_x = 1000
	root.add_child(player)
	player.set_physics_process(false)
	var frames := player.animated_sprite.sprite_frames
	var rows := PackedStringArray()
	for anim in frames.get_animation_names():
		var outlines := []
		for i in frames.get_frame_count(anim):
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			var path := tex.atlas.resource_path
			if not sheets.has(path):
				var image := Image.load_from_file(ProjectSettings.globalize_path(path))
				if image == null or image.is_empty():
					push_error("Cannot measure body sheet: " + path)
					quit(1)
					return
				sheets[path] = image
			var sheet: Image = sheets[path]
			outlines.append(outline(sheet.get_region(Rect2i(tex.region))))
		rows.append("\t%s:%s" % [JSON.stringify(anim), JSON.stringify(outlines)])
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error(error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string("{\n" + ",\n".join(rows) + "\n}\n")
	file.close()
	print("Baked visible body outlines for ", rows.size(), " animations")
	player.queue_free()
	quit()

func outline(image: Image) -> Array:
	# Hair, coat and boots isolate the figure from the blade and painted trails.
	var edges := PackedVector2Array()
	var used := image.get_used_rect()
	for y in range(used.position.y, used.end.y):
		var first := used.end.x
		var last := -1
		for x in range(used.position.x, used.end.x):
			if palette.has(image.get_pixel(x, y).to_rgba32()):
				first = mini(first, x)
				last = x
		if last > first:
			edges.append(Vector2(first, y))
			edges.append(Vector2(last + 1, y + 1))
	if edges.is_empty() and used.has_area():
		# Separately painted swim sheets use a different palette.
		edges = PackedVector2Array([used.position, Vector2i(used.end.x, used.position.y),
				used.end, Vector2i(used.position.x, used.end.y)])
	var result := []
	if not edges.is_empty():
		var hull := Geometry2D.convex_hull(edges)
		for i in hull.size() - 1:
			result.append(int(hull[i].x))
			result.append(int(hull[i].y))
	return result

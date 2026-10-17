extends SceneTree
## Offline only. Render the inventoried procedural source into trimmed RGBA atlas pages.
const Source = preload("pixel_slash_bake_source.gd")
const FPS := 60.0
const MAX_PAGE := 4096
var manifest := {"version": 1, "fps": FPS, "clips": {}}
var output := ""

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var manifest_path := output.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path): manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var recipes := {}
	var file := FileAccess.open(args[0], FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty(): continue
		var recipe: Dictionary = JSON.parse_string(line)
		recipes[recipe.key] = recipe
	file.close()
	var index := 0
	for key: String in recipes:
		index += 1
		var recipe: Dictionary = recipes[key]
		if manifest.clips.has(key): continue
		await bake(key, recipe.spec, String(recipe.get("asset_path", "combat_shared/uncategorized/vfx_%s" % key.substr(0, 10))))
		FileAccess.open(manifest_path, FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t", true))
		print("BAKED ", index, "/", recipes.size(), " ", recipe.get("asset_path", key))
	print("COMBAT VFX BAKE COMPLETE: ", manifest.clips.size(), " clips")
	quit()

func bake(key: String, encoded: Dictionary, asset_path: String) -> void:
	var spec: Dictionary = CombatVFXRecipe.decode(encoded)
	var source = Source.new().configure(spec)
	root.add_child(source)
	var total: float = source.duration + source.tail
	if source.shape == &"path": total = float(source._path.total) + source.tail
	elif source.shape == &"sparks": total = source.spark_life.y
	elif source.shape in [&"crescent", &"star"]: total = source.duration + source.hold + source.fade
	var times: Array[float] = [0.0]
	for frame in range(1, ceili(total * FPS) + 1): times.append(minf(frame / FPS, total))
	if source.shape in [&"crescent", &"star"]:
		times.append(source.duration)
		times.append(source.duration + source.hold)
	times.sort()
	var unique_times: Array[float] = []
	for t in times:
		if unique_times.is_empty() or t - unique_times[-1] > 0.000001: unique_times.append(t)
	var frames: Array = []
	var bounds := Rect2i()
	for t in unique_times:
		if t > source.age: source.advance(t - source.age)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = source._viewport.get_texture().get_image()
		var used := image.get_used_rect()
		if used.has_area():
			bounds = bounds.merge(used) if bounds.has_area() else used
			frames.append({"rect": used, "png": image.get_region(used).save_png_to_buffer()})
		else: frames.append({"rect": Rect2i(), "png": PackedByteArray()})
	# One fixed pivot for every frame prevents wobble; transparent padding protects edges.
	if not bounds.has_area(): bounds = Rect2i(0, 0, 1, 1)
	bounds = bounds.grow(1).intersection(Rect2i(Vector2i.ZERO, source._viewport.size))
	var cell := bounds.size
	var columns := maxi(1, mini(8, MAX_PAGE / cell.x))
	var rows := maxi(1, mini(8, MAX_PAGE / cell.y))
	var capacity := columns * rows
	var pages: Array[String] = []
	var name := asset_path.get_file()
	DirAccess.make_dir_recursive_absolute(output.path_join(asset_path.get_base_dir()))
	for first in range(0, frames.size(), capacity):
		var count := mini(capacity, frames.size() - first)
		var page_rows := ceili(float(count) / columns)
		var sheet := Image.create(cell.x * columns, cell.y * page_rows, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)
		for local in count:
			var frame: Dictionary = frames[first + local]
			if not frame.rect.has_area(): continue
			var image := Image.new()
			image.load_png_from_buffer(frame.png)
			var offset: Vector2i = frame.rect.position - bounds.position
			var at := Vector2i(local % columns, local / columns) * cell + offset
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		var page_name := "%s_%02d.png" % [asset_path, pages.size()]
		sheet.save_png(output.path_join(page_name))
		pages.append(page_name)
	var pivot: Vector2 = Vector2(source._viewport.size) * 0.5 - Vector2(bounds.position)
	manifest.clips[key] = {"name": name, "asset_path": asset_path, "spec": encoded, "pages": pages,
		"cell": [cell.x, cell.y], "columns": columns, "capacity": capacity,
		"pivot": [pivot.x, pivot.y], "times": unique_times, "duration": total,
		"pixel_size": source.pixel_size, "frames": frames.size()}
	source.free()

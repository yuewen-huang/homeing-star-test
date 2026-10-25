extends SceneTree
## Render every existing comic panel, inspect source edges, and exercise advancement.

const SCENES := [
	"res://scenes/story/comics/back_alley_entry_comic.tscn",
	"res://scenes/story/comics/back_alley_pill_comic.tscn",
	"res://scenes/story/comics/navigation_hall_entry_comic.tscn",
	"res://scenes/story/comics/navigation_hall_exit_comic.tscn",
	"res://scenes/story/comics/master_dodge_comic.tscn",
]
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func press() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func has_ink_or_gutter_edge(image: Image) -> bool:
	# A near-solid neutral line across almost the entire edge indicates frame ink
	# or page gutter, rather than a naturally dark/bright part of the illustration.
	for edge in 4:
		var length := image.get_width() if edge < 2 else image.get_height()
		var ink := 0
		var paper := 0
		for p in range(4, length - 4):
			var x := p if edge < 2 else (0 if edge == 2 else image.get_width() - 1)
			var y := (0 if edge == 0 else image.get_height() - 1) if edge < 2 else p
			var color := image.get_pixel(x, y)
			var high := maxf(color.r, maxf(color.g, color.b))
			var low := minf(color.r, minf(color.g, color.b))
			if high - low < 20.0 / 255.0:
				if high < 45.0 / 255.0: ink += 1
				if low > 220.0 / 255.0: paper += 1
		if float(maxi(ink, paper)) / float(length - 8) > 0.98:
			return true
	return false

func inspect(comic: Node, name: String) -> void:
	var presentation := comic as ComicPlayer
	check(presentation != null, name + " uses the shared ComicPlayer")
	check(presentation.layer == 900, name + " covers global gameplay HUD below scene fade")
	check(comic._image.offset_bottom <= -48.0, name + " leaves a dedicated prompt area")
	check(comic._image.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, name + " uses smooth comic scaling")
	check(comic._hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and comic._hint.get_theme_font_size("font_size") == 18 \
		and comic._hint.offset_top == -40.0 and comic._hint.offset_bottom == -8.0,
		name + " uses the common bottom hint style")
	for i in comic.PANELS.size():
		check(comic.panel_index == i, "%s panel %d advances in original order" % [name, i + 1])
		var texture: AtlasTexture = comic._panel_texture
		var bounds := Rect2(Vector2.ZERO, texture.atlas.get_size())
		check(bounds.encloses(texture.region) and texture.region.has_area(), "%s panel %d stays inside source" % [name, i + 1])
		var page := texture.atlas.get_image()
		if page.is_compressed(): page.decompress()
		var panel := page.get_region(Rect2i(texture.region))
		check(not has_ink_or_gutter_edge(panel), "%s panel %d excludes straight ink/gutter edges" % [name, i + 1])
		check(comic._image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Panel preserves original proportions")
		await capture("crop_%s_%02d" % [name, i + 1])
		if i + 1 < comic.PANELS.size():
			press()
			await create_timer(0.25).timeout

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var save := root.get_node("SaveProgress") as SaveProgressService
	save._config = ConfigFile.new()
	save._loaded = true
	save.progress_changed.emit()
	for path: String in SCENES:
		var comic: Node = load(path).instantiate()
		root.add_child(comic)
		current_scene = comic
		await process_frame
		await inspect(comic, path.get_file().get_basename())
		comic.free()
		current_scene = null
	var escape := AberrationEscapeComic.new()
	root.add_child(escape)
	await process_frame
	await inspect(escape, "aberration_escape_comic")
	var finished := [0]
	escape.finished.connect(func(): finished[0] += 1)
	press()
	await process_frame
	check(finished[0] == 1 and not is_instance_valid(escape), "Final escape panel completes once and cleans up")
	print("COMIC CROPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree

const ART_ROOT := "res://assets/sideview/environment/chapter_1_vine/"
var OUTPUT := ""

func _initialize() -> void:
	OUTPUT = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if OUTPUT.is_empty():
		OUTPUT = get_script().resource_path.get_base_dir().path_join("../artifacts/vine_midground")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	run.call_deferred()

func texture(path: String) -> ImageTexture:
	return ImageTexture.create_from_image(Image.load_from_file(ART_ROOT.path_join(path)))

func sprite(parent: Node, path: String, at: Vector2, width: float, tint := Color.WHITE) -> Sprite2D:
	var item := Sprite2D.new()
	item.texture = texture(path)
	item.position = at
	item.scale = Vector2.ONE * width / item.texture.get_width()
	item.modulate = tint
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(item)
	return item

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(name))

func run() -> void:
	root.size = Vector2i(1280, 720)
	var canvas := Node2D.new()
	root.add_child(canvas)
	var far := TextureRect.new()
	far.texture = texture("vine_forest_far.png")
	far.size = Vector2(1280, 720)
	far.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	far.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	far.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	canvas.add_child(far)
	var air := ColorRect.new()
	air.size = far.size
	air.color = Color(0.52, 0.67, 0.64, 0.28)
	canvas.add_child(air)
	sprite(canvas, "midground/groves/vine_grove_01_v2.png", Vector2(700, 350), 850, Color(0.70, 0.83, 0.79, 0.68))
	sprite(canvas, "midground/pieces/vine_branch_01.png", Vector2(465, 455), 820)
	sprite(canvas, "midground/pieces/vine_trunk_01.png", Vector2(210, 345), 500)
	sprite(canvas, "midground/pieces/vine_foliage_01.png", Vector2(350, 402), 470)
	await capture("vine_midground_composite_v2.png")
	canvas.queue_free()
	await process_frame
	var board := Node2D.new()
	root.add_child(board)
	var base := ColorRect.new()
	base.size = Vector2(1280, 720)
	base.color = Color("29383b")
	board.add_child(base)
	var paths := ["groves/vine_grove_01_v2.png", "pieces/vine_trunk_01.png", "pieces/vine_branch_01.png", "pieces/vine_foliage_01.png"]
	var labels := ["TREE GROUP", "TRUNK SECTION", "FORKED BRANCH", "FOLIAGE CLUSTER"]
	for i in 4:
		var item := sprite(board, "midground/" + paths[i], Vector2(160 + i * 320, 360), 280)
		var limit := 600.0 / item.texture.get_height()
		if item.scale.y > limit:
			item.scale = Vector2.ONE * limit
		var label := Label.new()
		label.position = Vector2(20 + i * 320, 20)
		label.add_theme_font_size_override("font_size", 19)
		label.text = labels[i]
		board.add_child(label)
	await capture("vine_midground_samples_v2.png")
	quit()

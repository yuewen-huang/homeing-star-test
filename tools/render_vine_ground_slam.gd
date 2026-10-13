extends SceneTree
## Offline raster preview, isolated from the production game and its saves.

func _initialize() -> void:
	call_deferred("render_preview")

func render_preview() -> void:
	var args := OS.get_cmdline_user_args()
	var source := args[0]
	var destination := args[1]
	var host := Node2D.new()
	root.add_child(host)
	var variants := ["01_细藤鞭", "02_粗藤重拍", "03_双藤重拍"]
	var frames := [6, 13, 19]
	if args.size() > 2:
		frames.clear()
		for value in args[2].split(","):
			frames.append(int(value))
	for col in 3:
		for row in 3:
			var image := Image.load_from_file(source.path_join("序列帧").path_join(variants[col]).path_join("%02d.png" % frames[row]))
			if image == null:
				push_error("Missing preview PNG")
				quit(1)
				return
			var sprite := Sprite2D.new()
			sprite.texture = ImageTexture.create_from_image(image)
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(2, 2)
			sprite.position = Vector2(col * 448, row * 480 + 24)
			host.add_child(sprite)
			var ground := Line2D.new()
			ground.add_point(Vector2(col * 448, row * 480 + 416))
			ground.add_point(Vector2((col + 1) * 448, row * 480 + 416))
			ground.width = 1
			ground.default_color = Color(0.28, 0.33, 0.26)
			host.add_child(ground)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(destination)
	print("GODOT VINE SLAM PREVIEW: ", error)
	quit(0 if error == OK else 1)

extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.unfocusable = true
	root.position = Vector2i(-1500, -1500)
	root.size = Vector2i(1280, 720)
	var packed = load("res://studies/sandstorm_scorpion/sandstorm_scorpion.tscn")
	if packed == null:
		quit(1)
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	for index in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png("D:/HomingStar/homeing-star-test/artifacts/sandstorm-scorpion-study/studio_native.png")
	print("Sand scorpion native capture: ", error)
	scene.queue_free()
	await process_frame
	quit(error)

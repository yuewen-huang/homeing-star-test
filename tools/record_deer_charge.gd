extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(folder)
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.play_action(3)
	for frame in 270:
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 3 == 0:
			var error := root.get_texture().get_image().save_png(folder.path_join("%03d.png" % (frame / 3)))
			if error != OK: quit(1); return
	print("CHARGE RECORD: 90 native frames")
	current_scene = null
	room.free()
	quit()

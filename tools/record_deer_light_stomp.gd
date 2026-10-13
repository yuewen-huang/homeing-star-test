extends SceneTree

var room

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for speed_index in [2, 0]:
		room.reset_room()
		await process_frame
		await process_frame
		room.set_playback_speed(speed_index)
		var speed: float = Engine.time_scale
		var folder := output.path_join("normal" if speed_index == 2 else "slow")
		DirAccess.make_dir_recursive_absolute(folder)
		room.play_action(0)
		for frame in int(102 / speed):
			await process_frame
			await RenderingServer.frame_post_draw
			if frame % 3 == 0:
				var error := root.get_texture().get_image().save_png(folder.path_join("%03d.png" % (frame / 3)))
				if error != OK: push_error("Capture failed"); quit(1); return
		var hit: Dictionary = room.dummy.contacts[0] if not room.dummy.contacts.is_empty() else {}
		print("CAPTURE ", folder, " contact=", hit)
		if hit.is_empty() or hit.first_frame != 7 or hit.last_frame != 8: quit(1); return
	room.free()
	quit()

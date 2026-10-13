extends SceneTree

const ROOMS := ["chapter_1_wind_boss_room", "chapter_1_special_boss_upper_right_room", "chapter_1_special_boss_lower_left_room", "chapter_1_root_heart_room", "chapter_1_final_boss_room"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	for room_name in ROOMS:
		var room := load("res://scenes/sideview/%s.tscn" % room_name).instantiate() as Chapter1BossRoom
		root.add_child(room)
		room.player.set_physics_process(false)
		if not room.arena_far or not room.arena_ground:
			push_error("Missing arena art: " + room_name)
			failures += 1
		if room.arena_ground.get_size() != Vector2(room.room_size.x,720-room.arena_ground_top):
			push_error("Ground size mismatch: " + room_name)
			failures += 1
		for frame in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(output.path_join(room_name + ".png"))
		print("ART CAPTURE: ", room_name, " ", image.get_size())
		if room.room_size.x > 1280:
			var floor_shape := room.get_node("Floor/CollisionShape2D").shape as RectangleShape2D
			if floor_shape.size.x != room.room_size.x or room.player.world_max_x != room.room_size.x-48:
				push_error("Wide arena collision or movement bounds mismatch")
				failures += 1
			for sample_x in [960.0,1280.0,2280.0]:
				room.player.position.x = sample_x
				room.player.set_physics_process(true)
				for frame in range(12):
					await process_frame
				room.player.set_physics_process(false)
				if absf(room.player.position.y-Chapter1BossRoom.FLOOR_Y)>3:
					push_error("Wide arena has no supporting floor at sample position")
					failures += 1
				await RenderingServer.frame_post_draw
				var camera := room.get_node("Camera2D") as Camera2D
				var expected_x := clampf(sample_x,640,room.room_size.x-640)
				if absf(camera.get_screen_center_position().x-expected_x)>1:
					push_error("Wide arena camera does not track player")
					failures += 1
				root.get_texture().get_image().save_png(output.path_join("final_wide_%d.png" % int(sample_x)))
				print("WIDE CAMERA: player ", sample_x, " camera ", camera.get_screen_center_position())
		root.remove_child(room)
		room.free()
	print("ARENA ART CHECKS: ", failures, " failures")
	quit(failures)

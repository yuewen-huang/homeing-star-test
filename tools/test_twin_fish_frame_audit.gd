extends SceneTree
## Record every displayed frame and movement sample from the actual room.
## This is an inspection artifact, not an artistic acceptance test.

func _initialize() -> void: call_deferred("run")

func fish_sample(fish: TwinFishSwimmer, sprite: TwinFishRigSprite) -> Dictionary:
	var joints := sprite.global_joints()
	var points := []
	for p in joints: points.append([p.x, p.y])
	return {"frame": fish.frame_index, "action": fish.action_name, "action_age": fish.action_age,
		"mirror": fish.mirrored, "heading": fish.heading, "draw_heading": sprite.current_heading,
		"rotation": fish.body_rotation, "position": [fish.position.x, fish.position.y],
		"registration": [fish.root_registration.x, fish.root_registration.y],
		"velocity": [fish.velocity.x, fish.velocity.y], "turning": fish.turning, "joints": points}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var arg := args.find("--visual-dir")
	var capture := arg >= 0 and DisplayServer.get_name() != "headless"
	if capture:
		output = args[arg + 1]
		DirAccess.make_dir_recursive_absolute(output)
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.boss_picker.item_selected.emit(2)
	await process_frame
	room.player.set_physics_process(false)
	var twin: TwinFishBoss = room.adapter.boss
	twin.set_physics_process(false)
	twin._swim_random.seed = 41019
	twin.start_arrival()
	var records := []
	for index in 32 * 60:
		if index > 0: twin.advance_action(1.0 / 60.0)
		records.append({"index": index, "time": float(index) / 60.0,
			"white": fish_sample(twin.white_swimmer, twin.white_sprite),
			"black": fish_sample(twin.black_swimmer, twin.black_sprite)})
		if capture:
			room._process(0.0)
			room.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("movie_%03d.png" % index))
	var path := output.path_join("fish_frames.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"fps": 60, "frames": records}))
	file.close()
	print("FRAME AUDIT: ", path)
	room.free()
	quit()

extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(not args.is_empty(), "Pass a screenshot output directory")
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.select_combo(2)
	room.play_action(2)
	for frame in 100:
		for i in 3:
			deer._physics_process(1.0/60.0)
			room._physics_process(1.0/60.0)
			deer.vfx._process(1.0/60.0)
		room._process(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%03d.png" % frame))
	current_scene = null
	room.free()
	quit()

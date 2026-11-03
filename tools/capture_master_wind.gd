extends "../tests/support/harness.gd"
## Engine rendering, not desktop capture. Fixed action clock makes comparisons repeatable.
func run() -> void:
	use_memory_progress()
	var output := OS.get_environment("HOMING_STAR_CAPTURE_DIR")
	if output.is_empty(): output = "D:/HomingStar/homeing-star-test/artifacts/master-wind-before"
	DirAccess.make_dir_recursive_absolute(output)
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	room.set_playback_speed(2)
	var triple := "--triple" in OS.get_cmdline_user_args()
	room.play_action(1 if triple else 2)
	var master: MasterBoss = room.adapter.master
	master.set_process(false)
	room.player.set_physics_process(false)
	var wind: MasterTornado
	for frame in (301 if triple else 211):
		if frame > 0:
			for child in master.get_children():
				if child is MasterChopImpact:
					child.set_process(false)
					child.advance(1.0 / 60.0)
			if is_instance_valid(wind) and wind.active and wind.get_parent() == master:
				wind.set_process(false)
				wind.advance(1.0 / 60.0)
			if master.phase_1_action != null:
				master.phase_1_action.advance(1.0 / 60.0)
				if master.phase_1_action != null and is_instance_valid(master.phase_1_action.sword_qi):
					wind = master.phase_1_action.sword_qi as MasterTornado
					wind.set_process(false)
		for child in master.get_children():
			if child is MasterChopImpact: child.set_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%04d.png" % frame))
	if not triple: check(is_instance_valid(wind), "Capture contains the released tornado")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER WIND CAPTURE")

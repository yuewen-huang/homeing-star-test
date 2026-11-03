extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	room.set_combat_simulation(true)
	var boss: MasterBoss = room.adapter.master
	var player: LanPlayer = room.player
	boss.set_process(false)
	player.set_physics_process(false)
	player.reset_after_map_fall(boss.global_position + Vector2(-180, 0))
	player.facing_direction = 1
	player.apply_facing_direction()
	player.play_walk()
	var output := "D:/HomingStar/homeing-star-test/artifacts/master-body-spacing"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 90:
		player.velocity = Vector2(180, 0)
		player.move_on_action_clock()
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [0, 30, 60, 89]: root.get_texture().get_image().save_png(output.path_join("%03d.png" % frame))
	check(absf(player.global_position.x - boss.global_position.x) >= boss.get_node("BodySpacing").gap_for(player) - 0.01, "Held forward input cannot overlap the master")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER BODY SPACING CAPTURE")

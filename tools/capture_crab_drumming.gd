extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(8)
	room.set_playback_speed(2)
	var crab: CrystalCrabBoss = room.adapter.crab
	crab.set_physics_process(false)
	crab.position.x = 600
	crab.start_quake(&"flurry", Vector2(1000,555))
	var output := "D:/HomingStar/homeing-star-test/artifacts/crab-drumming"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 245:
		crab._physics_process(1.0/60)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(output.path_join("%04d.png" % frame))
	check(is_equal_approx(crab.position.x, 690), "Committed drumming advances only ninety pixels")
	check(crab.rhythm == null and crab.attack_hitbox.attack == null, "Recovery completes with no remaining damage")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("CRAB DRUMMING CAPTURE")

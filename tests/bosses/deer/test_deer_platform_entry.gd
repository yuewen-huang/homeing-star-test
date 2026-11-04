extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room: BossDevelopmentRoom = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	var deer := room.adapter.boss as DeerRootDuelBoss
	room.set_physics_process(false)
	deer.set_physics_process(false)
	room.player.set_physics_process(false)
	var camera := room.get_node("Camera2D") as Camera2D
	var baseline := camera.offset
	var stages := [10,33,65,95,130,165]
	var moving_soil := false
	for f in 166:
		deer.terrain.advance(1.0/60)
		deer._ground_body()
		moving_soil = moving_soil or not deer.terrain.pulses.is_empty()
		if f in stages:
			await process_frame
			RenderingServer.force_draw(false)
			await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("earth_entry_%03d.png" % f))
	check(moving_soil,"Entrance emits soil clods and dust at the ground seam")
	check(camera.offset==baseline,"Ground tremor restores the camera exactly")
	check(is_equal_approx(deer.terrain.roots[0].progress,1),"Rigid platform finishes at authored height")
	check(deer.terrain.roots.size()==1,"Earth heaves never spawn additional platforms")
	check(deer.attack_probes().is_empty(),"Stage emergence has no attack collision")
	expect_save_untouched()
	finish("EARTH PLATFORM ENTRY")

extends "../tests/support/harness.gd"
## Native production AI observation; scripted spacing is not a human playtest.
func run() -> void:
	use_memory_progress()
	var output := OS.get_environment("HOMING_STAR_CAPTURE_DIR")
	if output.is_empty(): output = "D:/HomingStar/homeing-star-test/artifacts/master-ai-remake"
	DirAccess.make_dir_recursive_absolute(output)
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	room.set_playback_speed(2)
	room.set_combat_simulation(true)
	var master: MasterBoss = room.adapter.master
	var player: LanPlayer = room.player
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	player.set_physics_process(false)
	master.phase_1_ai.rng.seed = 173
	player.global_position = master.global_position + Vector2(-160, 0)
	var seen := {}
	var serial := -1
	for frame in (0 if "--food" in OS.get_cmdline_user_args() else 1200):
		if frame == 60: player.global_position = master.global_position + Vector2(-250, 0)
		if frame == 420: player.global_position = master.global_position + Vector2(-360, 0)
		if frame == 800: player.global_position = master.global_position + Vector2(-150, 0)
		if master.phase_1_action != null and master.attack_serial != serial:
			serial = master.attack_serial
			seen[master.phase_1_action.id] = true
			print("AI frame=", frame, " action=", master.phase_1_action.id)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 4 == 0:
			root.get_texture().get_image().save_png(output.path_join("%04d.png" % frame))
	if not seen.is_empty(): check(seen.has(&"vertical") and seen.has(&"combo_three"), "Autonomous AI performs accepted melee exchanges")
	master.set_process(false)
	master._cancel_phase_1_action()
	master.start_food_mechanism()
	var food := master.food_mechanism
	food.advance(food._seating_time + 0.01)
	food._say("歇歇，陪为师吃两口。")
	for frame in 180:
		food.advance(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [0, 45, 90, 150]:
			root.get_texture().get_image().save_png(output.path_join("food_%03d.png" % frame))
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER AI OBSERVATION")

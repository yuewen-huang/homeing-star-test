extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	room.set_playback_speed(2)
	room.set_combat_simulation(true)
	var boss: MasterBoss = room.adapter.master
	var player: LanPlayer = room.player
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	player.reset_after_map_fall(boss.global_position + Vector2(-420, 0))
	boss.movement_direction = -1
	boss.start_phase_1_action(&"rise_unbalance")
	var health := player.combat_stats.health
	var pull := 0.0
	var start := player.global_position.x
	var before_contact := start
	var output := "D:/HomingStar/homeing-star-test/artifacts/master-tornado-combat"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 240:
		if boss.phase_1_action == null: boss.set_process(false)
		pull = maxf(pull, absf(player.horizontal_combat_wind()))
		if player.combat_stats.health == health: before_contact = player.global_position.x
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 4 == 0: root.get_texture().get_image().save_png(output.path_join("%04d.png" % frame))
	print("NATIVE pull_peak=", pull, " pre_hit_drag=", before_contact - start, " damage=", health - player.combat_stats.health)
	check(absf(before_contact - start) > 1.0, "Standing Lan visibly moves inward before projectile damage")
	check(pull > 30 and pull <= 105, "Native physics applies meaningful but capped inward wind")
	check(player.combat_stats.health < health, "Released tornado causes real distant damage")
	check(player.combat_winds.is_empty(), "No drag remains when the wind is gone")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER TORNADO COMBAT CAPTURE")

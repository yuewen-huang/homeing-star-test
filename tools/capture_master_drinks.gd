extends "../tests/support/harness.gd"
## Native autonomous progression under one overkill burst; scripted food/spacing driver.
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
	player.set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	boss.phase_1_ai.rng.seed = 173
	var output := "D:/HomingStar/homeing-star-test/artifacts/master-drink-progression"
	DirAccess.make_dir_recursive_absolute(output)
	boss.combat_stats.apply_health_damage(boss.combat_stats.max_health + 50)
	var captured := {}
	var layers := {}
	var saw_food := false
	for frame in 3600:
		var food := boss.food_mechanism
		if food != null:
			saw_food = true
			if food.stage == MasterFoodMechanism.Stage.COLLECT:
				if food.selected >= 0: player.global_position = boss.global_position + Vector2(-85, 0)
				else:
					for item in food.pickups:
						if item.kind == food.wanted:
							player.global_position = item.node.global_position
							break
		else:
			player.global_position = boss.global_position + Vector2(-150, 0)
		if not layers.has(boss.charged_power):
			layers[boss.charged_power] = frame
			print("NATIVE layer=", boss.charged_power, " frame=", frame, " hp=", boss.combat_stats.health, " bank=", boss.combat_stats.deferred_damage)
		await process_frame
		await RenderingServer.frame_post_draw
		var key := ""
		if boss.state == MasterBoss.State.DRINK and boss.animated_sprite.frame >= 6: key = "drink_%d" % (boss.charged_power + 1)
		elif food != null and food.stage == MasterFoodMechanism.Stage.COLLECT: key = "food"
		elif boss.charged_power == 4 and boss.state == MasterBoss.State.PHASE_1_ACTION: key = "fourth_exchange"
		elif boss.phase == 2: key = "phase_two"
		if not key.is_empty() and not captured.has(key):
			captured[key] = true
			root.get_texture().get_image().save_png(output.path_join(key + ".png"))
		if boss.phase == 2: break
	check(layers.size() == 5 and captured.has("drink_4"), "All four actual drink animations complete without callback shortcuts")
	check(saw_food and captured.has("food") and captured.has("fourth_exchange"), "Food and fourth-layer combat happen before transition")
	check(boss.phase == 2 and boss.combat_stats.deferred_damage == 0, "Native AI settles retained damage and reaches phase two")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER NATIVE DRINK PROGRESSION")

extends "../tests/support/harness.gd"
var results: Array[int] = []
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_combat_simulation(true)
	var deer: DeerBoss = room.adapter.deer
	var lan: LanPlayer = room.player
	deer.manual_control = true
	deer.test_vine_available = false
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	deer.attack_hitbox.hit_resolved.connect(func(_target, result): results.append(result))
	var shots := {}
	var output := "D:/HomingStar/homeing-star-test/artifacts/deer-mist-real-input"
	DirAccess.make_dir_recursive_absolute(output)
	for scenario in 3:
		deer.reset_phase(true,false)
		deer.short_stun_remaining = 0
		lan.reset_after_map_fall(Vector2(640,555))
		lan.combat_stats.restore_health()
		lan.parry_chain.cancel()
		for i in 20: await physics_frame
		var hp := lan.combat_stats.health
		results.clear()
		deer.start_mist_hunt()
		if scenario == 2:
			deer.test_vine_available = true
			key(KEY_Q,true)
			await physics_frame
			key(KEY_Q,false)
		if scenario == 1:
			deer._hunt_round = 2
			deer._start_hunt_round()
		var pressed := {}
		for frame in 900:
			key(KEY_K,false)
			key(KEY_L,false)
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
			if deer.state == DeerBoss.State.HUNT_WARNING and not pressed.has(-deer._hunt_round):
				Input.action_press(&"ui_left" if deer.direction > 0 else &"ui_right")
				pressed[-deer._hunt_round] = true
			if scenario != 2 and deer.state == DeerBoss.State.HUNT_CHARGE and not pressed.has(deer._hunt_round):
				var distance := absf(deer.global_position.x-lan.global_position.x)
				if distance < 225:
					key(KEY_L if scenario == 1 else KEY_K,true)
					pressed[deer._hunt_round] = true
			await physics_frame
			if deer.state == DeerBoss.State.HUNT_WARNING and absf(deer._time-deer.mist_warning_duration()+.1)<.025:
				var shot := "scenario_%d_round_%d" % [scenario,deer._hunt_round]
				if not shots.has(shot):
					shots[shot] = true
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output.path_join(shot+".png"))
			if not deer._hunt_active: break
		key(KEY_K,false)
		key(KEY_L,false)
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		print("REAL INPUT scenario=",scenario," contacts=",results," hp=",hp,"->",lan.combat_stats.health)
		if scenario == 0:
			check(results.count(CombatHitResult.Type.PARRY_SUCCESS) == 2 and deer._hunt_round == 2 and not deer._hunt_active, "Actual K inputs parry normal then red and end the hunt without a relic")
		elif scenario == 1:
			check(results.has(CombatHitResult.Type.EVADED), "Actual L input evades the gold hunt attack without a relic")
		else:
			check(deer.snared and deer.mist_phase.trap_remaining == 0, "Actual Q plants a physical trap and catches the oncoming horns")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("snare.png"))
		check(lan.combat_stats.health == hp, "Successful real-input defense takes no damage")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("DEER MIST REAL INPUT")

extends "test_master_phase2_readability.gd"

const CHASE := MasterPhase2BodyAction.CHASE_FIVE
const QUAKE := MasterPhase2BodyAction.RISING_QUAKE


func run() -> void:
	setup_room()
	await check_chase()
	var start := Engine.get_process_frames()
	await check_quake(true)
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		await check_quake(false)
		await check_finale_red_counter()
	else:
		var dir := args[0]
		var clip := {"id": "phase_2_quake", "scene": "tutorial", "phase": 2, "enemies": ["master"],
			"attack_speed": 1.76, "no_damage": lan.combat_stats.health == lan.combat_stats.max_health,
			"parries": parries, "dodges": dodges, "wave_jumped": true, "punish_hits": boss_hits,
			"start_frame": start, "end_frame": Engine.get_process_frames(), "fps": 60}
		FileAccess.open(dir.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify([clip], "\t"))
		FileAccess.open(dir.path_join("events.json"), FileAccess.WRITE).store_string("[]")
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER PHASE TWO FOLLOWUP")


func check_chase() -> void:
	prepare(BattleAssistSettingsService.Difficulty.NORMAL)
	var start_x := boss.position.x
	lan.reset_after_map_fall(boss.position + Vector2(-550, 0))
	await wait_frames(20)
	boss.start_phase_2_body_action(CHASE)
	var action := boss.phase_2_body_action
	var speed := boss.get_phase_2_attack_speed()
	var beats := action._attack_groups
	check(is_equal_approx(speed, 1.76), "The pursuit uses four stacks and the circle")
	check(beats.map(func(beat: Dictionary) -> int: return beat.danger) == [RED, NORMAL, RED, GOLD, NORMAL],
		"Pursuit goes red dash, shared three claws, then a separate ordinary tail")
	check((float(beats[3].release) - action._gold_prepare_at) / speed >= .25,
		"The double-claw lift is readable in the pursuit after the warp even at full speed")

	var pressed := {}
	var moved_back := false
	while boss.phase_2_body_action != null:
		await process_frame
		if boss.phase_2_body_action == null: break
		key(KEY_L, false)
		Input.action_release(&"parry")
		if not pressed.has(0) and action.elapsed >= .56:
			pressed[0] = true
			key(KEY_L, true)
			Input.action_press(&"ui_left")
		if action.elapsed >= .75 and not moved_back:
			Input.action_release(&"ui_left")
			Input.action_press(&"ui_right")
			moved_back = true
		for index in [1, 3, 4]:
			if pressed.has(index): continue
			var left := (float(beats[index].release) - action.elapsed) / speed
			if left > (.01 if index == 3 else .14): continue
			pressed[index] = true
			if index == 3:
				Input.action_press(&"ui_right")
				key(KEY_L, true)
			else:
				Input.action_press(&"parry")
		if action.elapsed >= 3.2 or (moved_back and action.elapsed < 3.0
				and absf(lan.position.x - boss.position.x) <= 110.0):
			Input.action_release(&"ui_right")
	Input.action_release(&"parry")
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_left")
	check(absf(boss.position.x - start_x) > 400.0, "The dash really relocates to the distant player")
	check(lan.combat_stats.health == lan.combat_stats.max_health and dodges == 2 and parries == 1,
		"The player evades the dash and gold claw, then actually parries the separate tail")
	check(boss.has_phase_2_punish_window() and is_equal_approx(boss.phase_2_idle_remaining, 1.2),
		"Only the landed tail starts the 1.2-second counterattack window")
	await punish(true)
	check(boss_hits == 2, "Two close strikes land within the completed pursuit's window")
	await wait_frames(10)


func check_quake(jump_wave: bool) -> void:
	prepare(BattleAssistSettingsService.Difficulty.NORMAL)
	boss.phase_2_finale_active = true
	await wait_frames(20)
	boss.start_phase_2_body_action(QUAKE)
	var action := boss.phase_2_body_action
	var speed := boss.get_phase_2_attack_speed()
	var beats := action._attack_groups
	var ground: Dictionary = action.vfx.definition.events.back()
	check(is_equal_approx(speed, 1.76), "The quake finale uses four stacks and the circle")
	check((float(beats[2].release) - action._gold_prepare_at) / speed >= .25,
		"The sustained gold flurry has a distinct pre-swing body cue")
	check((float(ground.t) - action._gold_end_at) / speed >= .33,
		"The gold group is off before the independent jump cue and travelling ground front")
	var pressed := {}
	var did_jump := false
	var saw_strip := false
	var jump_sent := false
	while boss.phase_2_body_action != null:
		await process_frame
		if boss.phase_2_body_action == null: break
		key(KEY_L, false)
		Input.action_release(&"parry")
		for index in [0, 2]:
			if pressed.has(index): continue
			var left := (float(beats[index].release) - action.elapsed) / speed
			if left > (.01 if index == 2 else .14): continue
			pressed[index] = true
			if index == 2:
				key(KEY_L, true)
			else:
				Input.action_press(&"parry")
		if Input.is_physical_key_pressed(KEY_L):
			Input.action_press(&"ui_right")
		if action.elapsed < action._gold_end_at:
			continue
		saw_strip = saw_strip or action.vfx._quake_warning._used > 0
		for cue in action.vfx.ground_cues():
			var left := (float(cue.release) - action.elapsed) / speed
			if not jump_sent and left <= .14:
				jump_sent = true
				if jump_wave: Input.action_press(&"jump")
			if left < .08: Input.action_release(&"jump")
		did_jump = did_jump or lan.air_state == LanPlayer.AirState.RISING
		if did_jump and absf(lan.position.x - boss.position.x) <= 96.0:
			Input.action_release(&"ui_right")
	Input.action_release(&"jump")
	Input.action_release(&"parry")
	Input.action_release(&"ui_right")
	check(saw_strip and dodges == 1 and parries == 2, "Gold flurry is one dodge and has its own cue before the ground strip")
	if jump_wave:
		check(did_jump and lan.combat_stats.health == lan.combat_stats.max_health,
			"Real W after the dodge passes over the independently timed front")
		check(boss.has_phase_2_punish_window() and is_equal_approx(boss.phase_2_idle_remaining, 1.6),
			"The finished front and low claws start the full finale window")
		await punish(true)
		check(boss_hits == 2, "Two close strikes land after the quake")
		await wait_frames(12)
	else:
		check(not did_jump and lan.combat_stats.health == lan.combat_stats.max_health - CombatTuning.BOSS_PLAYER_GOLD_DAMAGE,
			"The identical dodge without W avoids the claws and takes the ground hit")


func check_finale_red_counter() -> void:
	prepare(BattleAssistSettingsService.Difficulty.HARD)
	await wait_frames(20)
	boss.phase_2_buff_remaining = boss.PHASE_2_FINALE_LEAD
	boss._start_phase_2_finale(lan.position.x - boss.position.x)
	await defend(boss.phase_2_body_action, true, false)
	check(red_counters == 1 and boss.phase_2_body_action == null and not boss.phase_2_finale_active
		and not boss.phase_2_magic_circle.visible and boss.phase_2_howl_cooldown_remaining > 8.0,
		"A manual red counter ends the finale and cleans its pending ground front")
	await wait_frames(120)
	check(boss.combat_stats.health > 0 and not boss.phase_2_finale_active,
		"Normal AI resumes after the interrupted finale")

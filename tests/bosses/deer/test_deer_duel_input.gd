extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var contacts: Array[int] = []

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func release_inputs() -> void:
	for code in [KEY_K,KEY_L,KEY_W,KEY_J]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer = room.adapter.boss
	lan = room.player
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	# Both directions: ordinary jump, K + J punish, sweep K + J, walking off drop,
	# jumping low leaf then landing beneath high return, leaf K destroys the return.
	for facing in [-1,1]:
		for sample in 9:
			var scenario := sample if sample < 7 else 0
			var jump_at := .60 if sample < 7 else (.50 if sample == 7 else .66)
			release_inputs()
			room._combat_result = ""
			lan.set_input_frozen(false)
			deer.restart_duel()
			deer.wait_left = 999
			deer.position.x = 820 if facing < 0 else 360
			lan.reset_after_map_fall(Vector2(380 if facing < 0 else 800,555))
			lan.combat_stats.restore_health()
			lan.parry_chain.cancel()
			lan.facing_direction = -facing
			if scenario == 2: deer.position.x = lan.position.x-facing*225
			if scenario == 6: deer.position.x = lan.position.x-facing*100
			for f in 10: await physics_frame
			contacts.clear()
			var health := lan.combat_stats.health
			var boss_health := deer.combat_stats.health
			var index := 0 if scenario < 2 else (2 if scenario == 2 else (1 if scenario == 3 else 3))
			deer.start_move(index,lan.position.x)
			var pressed := false
			var punished := false
			var saw_opening := false
			var opening_at := -1.0
			var openings := 0.0
			for frame in 600:
				key(KEY_K,false)
				key(KEY_J,false)
				var t := deer.age
				if scenario == 6 and not punished and t >= 1.05:
					key(KEY_J,true)
					punished = true
				# Jump on the final windup; the faster burst can no longer be treated
				# as the old slow traversal. K remains a contact-timed response.
				if not pressed and scenario == 0 and t >= jump_at:
					key(KEY_W,true)
					pressed = true
				if not pressed and scenario == 1 and t >= .68 and absf(deer.position.x-lan.position.x) < 295:
					key(KEY_K,true)
					pressed = true
				if not pressed and scenario == 2 and t >= .48:
					key(KEY_K,true)
					pressed = true
				if scenario == 3:
					if t > .28 and deer.opening <= 0: Input.action_press(&"ui_left" if facing < 0 else &"ui_right")
					else:
						Input.action_release(&"ui_left")
						Input.action_release(&"ui_right")
				if not pressed and scenario in [4,5] and t >= DeerDuelBoss.LEAF_RELEASE:
					var gap := absf(deer.leaf_world_at(t-DeerDuelBoss.LEAF_RELEASE).x-lan.position.x)
					if gap < (125 if scenario == 4 else 70):
						key(KEY_W if scenario == 4 else KEY_K,true)
						pressed = true
				if deer.opening > 0:
					if not saw_opening: opening_at = deer.opening
					saw_opening = true
					openings += 1.0/60
					key(KEY_W,false)
					if scenario in [0,1,2,3] and not punished:
						# Walk towards the actual stopped body, then use a real J press.
						var gap := deer.position.x-lan.position.x
						if absf(gap) > 155: Input.action_press(&"ui_left" if gap < 0 else &"ui_right")
						elif lan.air_state == LanPlayer.AirState.GROUNDED:
							Input.action_release(&"ui_left")
							Input.action_release(&"ui_right")
							lan.facing_direction = signf(gap)
							key(KEY_J,true)
							punished = true
				await physics_frame
				if saw_opening and deer.move == &"":
					deer.wait_left = 999
					break
			release_inputs()
			print("DUEL INPUT scenario=",scenario," direction=",facing," jump_at=",jump_at," contacts=",contacts," HP=",health,"->",lan.combat_stats.health," punish=",boss_health-deer.combat_stats.health," opening=",opening_at," elapsed=",openings)
			check(saw_opening,"Scenario %d facing %d completes a move" % [scenario,facing])
			check(lan.combat_stats.health == health,"Scenario %d facing %d is avoidable with real input" % [scenario,facing])
			if scenario in [1,2,5]:
				check(contacts.count(CombatHitResult.Type.PARRY_SUCCESS) == 1,"Scenario %d facing %d real K parries once" % [scenario,facing])
				var natural_opening: float = {1:1.0,2:17.0/12.0+.1,5:.60}[scenario]
				check(absf(opening_at-natural_opening)<.04,"Defense reaches the authored end recovery without an extra parry stun")
			if scenario in [0,1,2,3]: check(deer.combat_stats.health < boss_health,"Real J fits after defense, facing %d scenario %d" % [facing,scenario])
			if scenario == 6: check(deer.combat_stats.health < boss_health,"Real J hits vulnerable body while leaf is flying")
	# Each complete phrase owns a group; natural follow-ups keep that same group.
	release_inputs()
	lan.combat_stats.restore_health()
	assist.set_player_invincible(true)
	deer.restart_duel()
	deer._rng.seed = 808
	var observed: Array[StringName] = []
	var chain_keys := {}
	deer.move_started.connect(func(id):
		observed.append(id)
		chain_keys[deer.get_parry_chain_key()] = true)
	for frame in 3600:
		await physics_frame
		if observed.size() >= 14: break
	check(observed.size() >= 14 and chain_keys.size() >= 4 and chain_keys.size() < observed.size(),"Autonomous phrases advance and preserve grouped follow-ups")
	check(observed.has(&"rush") and observed.has(&"sweep") and observed.has(&"drop") and observed.has(&"leaf"),"Actual autonomous fight uses all four moves")
	check(deer.phase == 1 and not deer.auto_advance_phases,"No later phases are enabled")
	print("AUTONOMOUS ORDER ",observed)
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER DUEL REAL INPUT")

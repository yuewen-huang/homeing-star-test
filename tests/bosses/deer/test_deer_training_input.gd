extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerTrainingBoss
var lan: LanPlayer
var contacts: Array[int] = []

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_training_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer = room.adapter.boss
	lan = room.player
	deer.attack_hitbox.hit_resolved.connect(func(_target, result): contacts.append(result))
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	for scenario in 9:
		assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL if scenario == 6 else BattleAssistSettingsService.Difficulty.HARD)
		for code in [KEY_K, KEY_L, KEY_W, KEY_J]: key(code, false)
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		deer.restart_slice()
		deer.wait_left = 999
		lan.reset_after_map_fall(Vector2(380, 555))
		lan.combat_stats.restore_health()
		lan.parry_chain.cancel()
		lan.facing_direction = 1
		if scenario in [4, 6, 8]: deer.position.x = 655
		for f in 8: await physics_frame
		var before := lan.combat_stats.health
		contacts.clear()
		var move := 3 if scenario in [2, 3] else (2 if scenario in [4, 6, 8] else (1 if scenario == 5 else 0))
		deer.start_exercise(move, lan.position.x)
		var pressed := {}
		var saw_opening := false
		for frame in 900:
			var t := deer.age
			key(KEY_K, false)
			key(KEY_L, false)
			if scenario in [2, 3, 5]:
				if t < .58 and deer.opening <= 0: Input.action_press(&"ui_left")
				else: Input.action_release(&"ui_left")
			if scenario == 8: Input.action_press(&"ui_left")
			if scenario in [0, 2] and t >= (.65 if scenario == 0 else 1.10) and not pressed.has(0):
				key(KEY_W, true)
				pressed[0] = true
			if scenario in [1, 3, 7] and not pressed.has(0) and t >= .65:
				if absf(deer.position.x - lan.position.x) <= 300:
					lan.facing_direction = 1
					key(KEY_L if scenario == 7 else KEY_K, true)
					pressed[0] = true
			if scenario in [4, 6]:
				for beat in 3:
					if scenario == 6 and beat > 0: continue
					if t >= DeerTrainingBoss.BEATS[beat] - .12 and not pressed.has(beat):
						lan.facing_direction = 1
						key(KEY_K, true)
						pressed[beat] = true
			await physics_frame
			if deer.opening > 0:
				saw_opening = true
				key(KEY_W, false)
			if saw_opening and deer.move == &"":
				deer.wait_left = 999
				break
		key(KEY_W, false)
		key(KEY_K, false)
		key(KEY_L, false)
		Input.action_release(&"ui_left")
		print("INPUT scenario=", scenario, " contacts=", contacts, " HP=", before, "->", lan.combat_stats.health, " position=", lan.position)
		check(saw_opening, "Real input scenario %d reaches a reaction window" % scenario)
		check(lan.combat_stats.health == before, "Real input scenario %d takes no damage" % scenario)
		if scenario in [1, 3]: check(contacts.count(CombatHitResult.Type.PARRY_SUCCESS) == 1, "K stops A in scenario %d" % scenario)
		if scenario in [4, 6]: check(contacts.count(CombatHitResult.Type.PARRY_SUCCESS) == 3, "C three shared parries in scenario %d" % scenario)
	# A real J press during recovery must connect; no direct receive_hit shortcut.
	deer.restart_slice()
	deer.wait_left = 999
	lan.reset_after_map_fall(Vector2(650, 555))
	lan.facing_direction = 1
	deer.position.x = 750
	deer.start_exercise(0, 650)
	deer._recover(1.3)
	var boss_health := deer.combat_stats.health
	key(KEY_J, true)
	await physics_frame
	key(KEY_J, false)
	for f in 60: await physics_frame
	check(deer.combat_stats.health < boss_health, "Actual J input damages boss in the counter window")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER TRAINING REAL INPUT")

extends "../tests/support/harness.gd"
## Record each lesson with its actual alley wave and stage-limited HUD.
var output := ""
var clips: Array[Dictionary] = []
var room: Node2D
var enemies_before := 0

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var progress := use_memory_progress()
	var quest_log := root.get_node("QuestLog")
	if quest_log._tracker != null: quest_log._tracker.hide()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	var ids := [&"normal_attack", &"instant_dash", &"jump_attack", &"dodge_combo", &"charged_attack", &"poise_throw"]
	for index in ids.size():
		var id: StringName = ids[index]
		var wave := mini(index + 1, 5)
		var unlocked := [SaveProgressService.ABILITY_MOVE, SaveProgressService.ABILITY_JUMP, SaveProgressService.ABILITY_CLIMB, SaveProgressService.ABILITY_ATTACK, SaveProgressService.ABILITY_CROUCH, SaveProgressService.ABILITY_SPECIAL_ITEM]
		if wave >= 2: unlocked.append(SaveProgressService.ABILITY_DASH)
		if wave >= 3: unlocked.append(SaveProgressService.ABILITY_AIR_ATTACK)
		if wave >= 4: unlocked.append(SaveProgressService.ABILITY_DODGE)
		if wave >= 5: unlocked.append(SaveProgressService.ABILITY_SPECIAL)
		progress.locked.clear()
		for ability: StringName in SaveProgressService.ABILITY_UNLOCK_PROGRESS:
			if ability not in unlocked: progress.locked.append(ability)
		room = load("res://scenes/levels/back_alley/back_alley.tscn").instantiate()
		root.add_child(room)
		current_scene = room
		var lan := room.player as LanPlayer
		var encounter: Node = room.encounter
		encounter.set_process(false)
		encounter.state = encounter.State.INTRO
		lan.position = Vector2(1180, room.FLOOR_Y)
		room.camera_x = 1250
		room.update_scroll()
		var frog: FroggerBoss
		if wave < 5:
			encounter.original_world_max_x = lan.world_max_x
			encounter._start_wave(wave, lan.position.x, false)
			if wave == 1: lan.position.x = encounter.live_enemies[0].position.x - 38
			if wave == 2: lan.position.x = encounter.live_enemies.back().position.x - LanPlayer.INSTANT_DASH_DISTANCE
			if wave == 3: lan.position.x = encounter.live_enemies[0].position.x - 50
			if wave == 4: lan.position.x -= 130
		else:
			encounter._enter_fifth_wave()
			encounter.state = encounter.State.INTRO
			frog = encounter.frog_boss
			frog.manual_control = true
			frog.set_physics_process(false)
			frog.position.x = lan.position.x + 95
		var keys := KeyHint.new()
		var labels: Array[String] = []
		for label in [["J"], ["U"], ["W", "J"], ["L", "J", "J", "J"], ["I"], ["E"]][index]: labels.append(label)
		keys.configure_labels(lan, labels, 0.36)
		room.add_child(keys)
		if encounter.key_hint != null: encounter.key_hint.hide()
		await wait_seconds(0.8)
		var initial_targets: Array[Dictionary] = []
		for enemy: Node2D in encounter.live_enemies:
			initial_targets.append({"node": enemy, "health": enemy.health})
		var start := Engine.get_process_frames()
		var before_health := frog.combat_stats.health if frog != null else 0
		await wait_seconds(0.4)
		match id:
			&"normal_attack":
				lan.start_attack_1x(1)
				await wait_seconds(0.65)
				lan.start_attack_2x(1)
				await wait_seconds(0.65)
				lan.start_attack_3x(1)
			&"instant_dash": lan.start_instant_dash(1)
			&"jump_attack":
				Input.action_press(&"jump")
				lan.start_jump()
				await wait_seconds(0.25)
				lan.start_jump_attack_1x(1)
				await wait_seconds(0.6)
				Input.action_release(&"jump")
			&"dodge_combo":
				lan.start_back_dodge(-1)
				await wait_seconds(0.25)
				lan.start_dodge_attack_1x(1)
				await wait_seconds(0.45)
				lan.cancel_uncommitted_attack_effects()
				lan.start_dodge_attack_2x(1)
				await wait_seconds(0.45)
				lan.cancel_uncommitted_attack_effects()
				lan.start_dodge_attack_3x(1)
			&"charged_attack":
				Input.action_press(&"special_attack")
				lan.start_special_attack(1)
				await wait_seconds(1)
				Input.action_release(&"special_attack")
			&"poise_throw":
				frog.combat_stats.apply_poise_damage(frog.combat_stats.max_poise)
				await wait_seconds(0.4)
				lan.perform_special_attack(1, 0, frog)
		await wait_seconds(2)
		var hit: bool = frog.combat_stats.health < before_health if frog != null else encounter.live_enemies.size() < [1, 3, 1, 6][wave - 1]
		for target in initial_targets:
			if not is_instance_valid(target.node) or target.node.health < target.health: hit = true
		check(hit, "%s settles a real hit on the current wave" % id)
		check(room.find_children("*", "MasterBoss", true, false).is_empty(), "No master combatant in alley take")
		check(not progress.is_ability_unlocked(SaveProgressService.ABILITY_ULTIMATE), "Future ultimate stays locked")
		clips.append({"id": id, "scene": "back_alley", "wave": wave, "enemies": ["frogger"] if wave == 5 else (["bat"] if wave == 3 else (["slime", "bat"] if wave == 4 else ["slime"])), "unlocked": unlocked, "hit_verified": hit, "start_frame": start, "end_frame": Engine.get_process_frames(), "fps": 60})
		current_scene = null
		room.free()
		await process_frame
		Engine.time_scale = 1
	FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify(clips, "\t"))
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string("[]")
	expect_save_untouched()
	finish("BACK ALLEY LESSON RECORDING")

func wait_seconds(seconds: float) -> void:
	for i in ceili(seconds * 60): await process_frame

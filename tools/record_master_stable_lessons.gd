extends "record_master_showcase.gd"
## Recorded in the real teaching room: hard difficulty, invincibility off, button
## inputs only. Collision evidence gates publishing each instructional clip.
var clips: Array[Dictionary] = []
var lesson_keys: KeyHint

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	lesson_keys = KeyHint.new()
	room.add_child(lesson_keys)
	lesson_keys.configure_labels(lan, ["K"], 0.36)
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	master.attack_hitbox.hit_resolved.connect(_contact)
	running = true
	for pair in [[&"master_ground_chain", &"press_return"], [&"master_blink_chain", &"blink_return"], [&"master_air_chain", &"air_plunge"], [&"master_heavy_chain", &"spin_delayed"]]:
		_reset_take()
		stage = String(pair[0])
		var start := Engine.get_process_frames()
		var before := total_parries
		var damage_before := damage_taken
		_log("take_start")
		await _wait(0.4)
		master.start_clash_rhythm(pair[1])
		driving = true
		for tick in 1000:
			await physics_frame
			if master.clash_rhythm == null and lan.defense_state == LanPlayer.DefenseState.NONE: break
		driving = false
		_stop_move()
		await _wait(0.5)
		var expected := 5 if pair[1] == &"spin_delayed" else 6
		check(total_parries - before == expected, "%s manual parries: %d/%d" % [stage, total_parries-before, expected])
		check(damage_taken == damage_before, "%s no damage, no invincibility" % stage)
		clips.append({"id": stage, "scene": "tutorial", "phase": 1, "enemies": ["master"], "start_frame": start, "end_frame": Engine.get_process_frames(), "fps": 60, "parries": total_parries-before, "no_damage": damage_taken == damage_before, "rhythm": String(pair[1]), "difficulty": "hard", "revision": "source_blade_paths_20261020", "trajectory_sha256": FileAccess.get_sha256("res://scripts/bosses/master/master_blade_trajectories.gd")})
		_log("take_end")
	running = false
	_release_inputs()
	FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify(clips, "\t"))
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	expect_save_untouched()
	finish("MASTER STABLE LESSONS")

func _drive_rhythm(r: MasterClashRhythm) -> void:
	for i in r.strikes.size():
		var strike := r.strikes[i]
		var left := float(strike.t) - r.elapsed
		if not strike.done and left >= 0.0 and left <= 0.20 and not pressed.has(i):
			pressed[i] = true
			_press(&"parry")
	for candidate in r.projectiles:
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion(): continue
		var qi := candidate as MasterSwordQi
		var key := qi.get_instance_id()
		if pressed.has(key): continue
		var shape := lan.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D
		var axis := qi.velocity.normalized()
		var half := shape.shape.get_rect().size * shape.global_scale.abs() * 0.5
		var target_radius := absf(axis.x) * half.x + absf(axis.y) * half.y
		var left := ((shape.global_position - qi.global_position).dot(axis) - MasterSwordQi.HITBOX_SIZE.x * 0.5 - target_radius) / MasterSwordQi.SPEED
		if left >= 0.0 and left <= 0.20:
			pressed[key] = true
			_press(&"parry")

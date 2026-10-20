extends "record_master_showcase.gd"
## Second-form footage, no invincibility and no first-form substitutions.
var clips: Array[Dictionary] = []
var keys: KeyHint
var take_start := 0
var take_action: StringName
var taken: Dictionary = {}
var wave_jumped := false
var driving_phase_2 := false
var jump_at := 0
var double_jumped := false

func run() -> void:
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
	keys = KeyHint.new()
	room.add_child(keys)
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	lan.dodge_evaded_attack.connect(func(_source: Node2D, _duration: float) -> void: dodges += 1)
	master.attack_hitbox.hit_resolved.connect(_contact)
	master._enter_phase_2()
	while master.state == MasterBoss.State.TRANSFORM: await physics_frame
	running = true
	for pair in [[&"phase_2_slash", &"phase_2_attack_1"], [&"phase_2_combo", &"phase_2_attack_2"], [&"phase_2_red_dash", &"phase_2_dash"], [&"phase_2_wave", &"phase_2_uppercut"], [&"phase_2_gold_chain", &"phase_2_dash"], [&"phase_2_poise_throw", &""], [&"ultimate", &""]]:
		if OS.get_cmdline_user_args().size() > 1 and String(pair[0]) != OS.get_cmdline_user_args()[1]: continue
		_reset_take()
		master.manual_control = false
		master.phase_2_buff_remaining = 0
		master.phase_2_finale_active = false
		master.phase_2_howl_cooldown_remaining = 100
		stage = String(pair[0])
		take_action = pair[1]
		taken.clear()
		wave_jumped = false
		double_jumped = false
		if stage == "phase_2_wave": lan.position.x = -280
		var labels: Array[String] = []
		if stage == "phase_2_gold_chain": labels = ["L"]
		elif stage == "phase_2_wave": labels = ["W", "W"]
		elif stage == "phase_2_poise_throw": labels = ["E"]
		elif stage == "ultimate": labels = ["O"]
		else: labels = ["K"]
		keys.configure_labels(lan, labels, 0.36)
		take_start = Engine.get_process_frames()
		_log("take_start")
		var before := total_parries
		var red_before := red_parries
		var dodge_before := dodges
		await _wait(0.5)
		if stage == "ultimate":
			master.set_process(false)
			lan.combat_stats.add_mana(100)
			lan.start_ultimate_combo()
			while lan.ultimate_active: await process_frame
			master.set_process(true)
		elif stage == "phase_2_poise_throw":
			master.combat_stats.apply_poise_damage(master.combat_stats.max_poise)
			await _wait(0.4)
			lan.perform_special_attack(1, 0, master)
			await _wait(1.5)
		else:
			master._face_phase_2_target(lan.position.x - master.position.x)
			if stage == "phase_2_gold_chain":
				master.phase_2_buff_remaining = 1.6
				master._start_phase_2_finale(lan.position.x - master.position.x)
			else:
				master._start_phase_2_attack(take_action)
			driving_phase_2 = true
			var ticks := 0
			while (master.state == MasterBoss.State.PHASE_2_ATTACK or master.red_parry_hold or _has_wave()) and ticks < 900:
				await physics_frame
				ticks += 1
			driving_phase_2 = false
			Input.action_release(&"jump")
		await _wait(0.8)
		check(lan.combat_stats.health == lan.combat_stats.max_health, "%s demonstrates defense without taking damage" % stage)
		if stage == "phase_2_slash": check(total_parries - before == 1, "Second-form slash settles one real parry")
		if stage == "phase_2_combo": check(total_parries - before == 3, "Second-form combo settles all three manual parries")
		if stage == "phase_2_red_dash": check(red_parries > red_before, "Second-form teleport settles a real red counter")
		if stage == "phase_2_gold_chain": check(dodges > dodge_before, "Gold chain settles real evasions")
		if stage == "phase_2_wave": check(wave_jumped, "Lan jumps the actual ground wave")
		if stage == "phase_2_poise_throw": check(master.combat_stats.health < master.combat_stats.max_health, "Second-form throw lands through production settlement")
		if stage == "ultimate": check(master.combat_stats.health < master.combat_stats.max_health, "Second-form ultimate lands through production settlement")
		clips.append({"id": stage, "scene": "tutorial", "phase": 2, "enemies": ["master"], "no_damage": lan.combat_stats.health == lan.combat_stats.max_health, "parries": total_parries - before, "red_parries": red_parries - red_before, "dodges": dodges - dodge_before, "wave_jumped": wave_jumped, "start_frame": take_start, "end_frame": Engine.get_process_frames(), "fps": 60})
		_log("take_end")
	running = false
	_release_inputs()
	FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify(clips, "\t"))
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	expect_save_untouched()
	finish("MASTER PHASE TWO LESSON RECORDING")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60): await process_frame

func _has_wave() -> bool:
	return room.get_children().any(func(child: Node) -> bool: return child is MasterGroundWave and not child.is_queued_for_deletion())

func _physics_process(delta: float) -> bool:
	super._physics_process(delta)
	if not running: return false
	if master.state == MasterBoss.State.PHASE_2_IDLE: master.phase_2_idle_remaining = 100
	if not driving_phase_2: return false
	if stage == "phase_2_wave":
		if wave_jumped and not double_jumped and Engine.get_physics_frames() - jump_at >= 18:
			double_jumped = true
			_press(&"jump")
		for child in room.get_children():
			if not child is MasterGroundWave or wave_jumped: continue
			var left: float = (lan.global_position.x - child.global_position.x) * child.travel_direction / MasterGroundWave.TRAVEL_SPEED
			if left > 0 and left <= 0.65:
				wave_jumped = true
				jump_at = Engine.get_physics_frames()
				_press(&"jump")
				_log("jump_wave")
		return false
	if master.state != MasterBoss.State.PHASE_2_ATTACK: return false
	var action := master.animated_sprite.animation
	var frames: Array = [8.0] if action == &"phase_2_attack_1" else ([6.0, 11.0, 24.0] if action == &"phase_2_attack_2" else ([6.0, 9.0, 15.0] if action == &"phase_2_special_attack" else [6.0]))
	var now := float(master.animated_sprite.frame) + master.animated_sprite.frame_progress
	var fps := master.animated_sprite.sprite_frames.get_animation_speed(action) * master.body_base_speed * master.get_action_time_scale()
	for index in frames.size():
		var key := "%s_%d" % [action, index]
		var left := (float(frames[index]) - now) / maxf(fps, 0.01)
		if left >= 0 and left <= (0.14 if stage == "phase_2_gold_chain" else 0.2) and not taken.has(key):
			taken[key] = true
			if stage == "phase_2_gold_chain": _dodge_near_master()
			else: _press(&"parry")
	return false

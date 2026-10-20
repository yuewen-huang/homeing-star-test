extends "record_master_showcase.gd"
## Directed production-room takes. Only button presses drive Lan; hits/parries/counters
## settle through production collision and feedback. Each take resets between clips.

var bullet_mode := false
var bullet_attacks := 0
var bullet_dodged := false
var attack_tick := 0

func run() -> void:
	# The production camera pulls out on the dive. Use black letterbox margins
	# for this recording instead of the editor's grey clear colour.
	load("D:/HomingStar/homeing-star-test/tools/recording_audio_mix.gd").apply(self)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://master_showcase"
	DirAccess.make_dir_recursive_absolute(output)
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	master = room.get_node("MasterBoss") as MasterBoss
	lan = room.get_node("Lan") as LanPlayer
	lan.separation_target = master
	var layer := CanvasLayer.new()
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(180, 95)
	caption.size = Vector2(920, 80)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 24)
	caption.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override(&"shadow_offset_x", 2)
	caption.add_theme_constant_override(&"shadow_offset_y", 2)
	layer.add_child(caption)
	caption.hide()
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	lan.dodge_evaded_attack.connect(func(source: Node2D, _duration: float) -> void:
		if source == master:
			dodges += 1
			_log("evade"))
	master.attack_hitbox.hit_resolved.connect(_contact)
	running = true
	for i in IDS.size():
		_reset_take()
		stage = String(IDS[i])
		caption.text = "脚本动作演示 · 普通难度 · 无敌关闭\n" + TITLES[i]
		_log("take_start")
		await _wait(0.8)
		var before := total_parries
		master.start_clash_rhythm(IDS[i])
		driving = true
		var ticks := 0
		while (master.clash_rhythm != null or lan.defense_state != LanPlayer.DefenseState.NONE) and ticks < 900:
			await physics_frame
			ticks += 1
		driving = false
		_stop_move()
		check(total_parries - before == [1, 2, 3, 2, 3, 0][i], "%s: real parry count %d" % [stage, total_parries-before])
		await _wait(0.7)
		_log("take_end")

	# Phase-two red teleport counter, using its ordinary frame-driven attack.
	_reset_take()
	stage = "phase_2_transform"
	caption.text = "脚本动作演示 · 真实碰撞判定\n师傅二阶段"
	_log("take_start")
	master._enter_phase_2()
	while master.state == MasterBoss.State.TRANSFORM: await physics_frame
	await _wait(0.8)
	_reset_take()
	stage = "phase_2_dash"
	caption.text = "脚本动作演示 · 无敌关闭\n二阶段瞬移 · 红刀反击"
	_log("take_start")
	await _wait(0.5)
	phase2_action = &"phase_2_dash"
	master._face_phase_2_target(lan.position.x - master.position.x)
	master._start_phase_2_attack(phase2_action)
	driving = true
	var counter_before := red_parries
	var wait_count := 0
	while (master.state == MasterBoss.State.PHASE_2_ATTACK or lan.defense_state != LanPlayer.DefenseState.NONE) and wait_count < 900:
		await physics_frame
		wait_count += 1
	driving = false
	phase2_action = &""
	check(red_parries > counter_before, "Phase-two dash settles a real red counter")
	await _wait(1.0)
	_log("take_end")
	for repeat in 2:
		_reset_take()
		stage = "bullet_time_attack_%d" % repeat
		bullet_mode = true
		bullet_dodged = false
		master.phase = 1
		master.play_idle()
		master.start_clash_rhythm(&"basic_down")
		driving = true
		await _wait(4.8)
		driving = false
		bullet_mode = false
		_stop_move()
	check(bullet_attacks > 0, "Attacks entered during real dodge bullet time")
	running = false
	_release_inputs()
	check(cue_captured, "First blade cue is rendered and captured")
	check(damage_taken == 0, "No health loss during the directed takes (%d)" % damage_taken)
	check(gold_landed and dodges > 0 and damage_taken == 0, "Gold landing played after real dodges, with no health loss")
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("MASTER SHOWCASE")

func _drive_rhythm(r: MasterClashRhythm) -> void:
	if not bullet_mode:
		super._drive_rhythm(r)
		return
	for i in r.strikes.size():
		var strike := r.strikes[i]
		var left := float(strike.t) - r.elapsed
		if not strike.done and left >= 0 and left <= 0.06 and not pressed.has(i):
			pressed[i] = true
			_key(KEY_L, true)
			release_keys.append(KEY_L)
			_log("bullet_dodge_input")

func _physics_process(delta: float) -> bool:
	super._physics_process(delta)
	if not bullet_mode or not running: return false
	if lan.dodge_bullet_time_remaining > 0:
		bullet_dodged = true
		var gap := master.position.x-lan.position.x
		_set_move(&"ui_right" if gap > 0 else &"ui_left")
		attack_tick += 1
		if attack_tick % 12 == 0:
			_key(KEY_J, true)
			release_keys.append(KEY_J)
		if lan.attack_state != LanPlayer.AttackState.NONE:
			bullet_attacks += 1
			if bullet_attacks == 1: _snapshot("bullet_time_attack")
	else:
		_stop_move()
	return false

extends "record_boss_reel.gd"
## Priority deer peaks: p2 根浪, p3 连震, p4 魔法轰炸 (ultimate 万鹿朝王 + herd + pierce).

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	kind = "deer"
	phase_index = int(args[2]) if args.size() > 2 else 3
	DirAccess.make_dir_recursive_absolute(output)
	use_memory_progress()
	RenderingServer.set_default_clear_color(Color.BLACK)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	load("D:/HomingStar/homeing-star-test/tools/recording_audio_mix.gd").apply(self)
	native_map = "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
	room = load(native_map).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	lan = room.player
	if is_instance_valid(room.story.comic):
		room.story._close_intro()
	boss = room.deer
	boss.manual_control = true
	boss.phase = phase_index
	boss.reset_phase()
	lan.input_frozen = false
	paused = false
	boss.set_physics_process(true)
	lan.separation_target = boss
	lan.max_target_separation_x = 1100.0
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
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(func(_r, _a, _p, red):
		parries += 1
		_log("red_parry" if red else "parry"))
	lan.dodge_evaded_attack.connect(func(source: Node2D, _duration: float) -> void:
		if source == boss:
			evades += 1
			_log("evade"))
	running = true
	if phase_index == 2:
		await _take("重踩 · 根浪", &"heavy", false, 6.0)
		await _take("快→快→慢 · 根浪连段", &"fast_fast_slow", false, 8.0)
	elif phase_index == 3:
		await _take("穿林五叠 · 连震", &"deer_phase3_forest_five", false, 7.0)
		await _take("踏岳六震 · 连震", &"deer_phase3_mountain_six", false, 8.0)
		await _take("回角逐风 · 连震", &"deer_phase3_return_four", false, 7.0)
	elif phase_index == 4:
		# Keep Lan alive: defeat transitions unload the room and free the player.
		lan.combat_stats.refill_health_on_depletion = true
		# Transform under manual_control so AI cannot open sequences mid-form.
		_reset()
		caption.text = "朽角巡林者 · 藤 · 化形"
		caption.show()
		boss.manual_control = true
		boss.start_vine()
		var transform_deadline := 12.0
		while transform_deadline > 0.0:
			var vine: DeerVinePhase = boss.vine_phase
			if vine.human and vine.step == DeerVinePhase.Step.HOVER:
				break
			await _wait(0.1)
			transform_deadline -= 0.1
		check(boss.vine_phase.human and boss.vine_phase.step == DeerVinePhase.Step.HOVER, "Deer vine hover after transform")
		await _vine_take(&"pierce_triple", "三连瞬刺 · 魔法连射", 14.0)
		await _vine_take(&"herd", "鹿群冲阵 · 魔法轰炸", 18.0)
		await _vine_take(&"ultimate", "万鹿朝王 · 魔法轰炸终章", 28.0)
	else:
		push_error("deer priority supports phase 2/3/4 only")
		failures += 1
	running = false
	_release()
	check(parries > 0, "Priority deer landed real parries: %d" % parries)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("DEER PRIORITY %d" % phase_index)

func _take(label: String, action: StringName, use_dodge: bool, seconds: float) -> void:
	_reset()
	take = String(action) + ("_dodge" if use_dodge else "")
	bullet = use_dodge
	caption.text = ("朽角巡林者 · %s · " % DeerBoss.PHASE_NAMES[phase_index - 1]) + label
	caption.show()
	_log("take_start")
	await _wait(0.5)
	driving = true
	pressed.clear()
	boss.manual_control = false
	if phase_index == 3:
		boss.start_clash(action, lan.position.x)
	elif action == &"heavy":
		boss.start_attack(DeerBoss.State.HEAVY)
	elif action == &"light":
		boss.start_attack(DeerBoss.State.LIGHT)
	else:
		boss.start_combo(action)
	await _wait(seconds)
	driving = false
	bullet = false
	boss.manual_control = true
	_release()
	_log("take_end")
	await _wait(0.4)

func _vine_take(action: StringName, label: String, seconds: float) -> void:
	# Soft reset only — full _reset() repositions the boss and can drop vine form.
	take = String(action)
	caption.text = "优先高燃 · 藤 · " + label
	caption.show()
	pressed.clear()
	bullet = false
	lan.combat_stats.refill_health_on_depletion = true
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	last_hp = lan.combat_stats.health
	_log("take_start")
	await _wait(0.4)
	# Wait until hover-ready between sequences.
	var ready_wait := 6.0
	while ready_wait > 0.0 and boss.vine_phase.step not in [DeerVinePhase.Step.HOVER, DeerVinePhase.Step.CAST, DeerVinePhase.Step.BLINK, DeerVinePhase.Step.HOLD]:
		await _wait(0.1)
		ready_wait -= 0.1
	boss.manual_control = true
	var started: bool = boss.start_vine(action)
	if not started:
		var retry := 4.0
		while retry > 0.0:
			await _wait(0.1)
			retry -= 0.1
			if boss.vine_phase.human and boss.vine_phase.step in [DeerVinePhase.Step.HOVER, DeerVinePhase.Step.CAST, DeerVinePhase.Step.BLINK, DeerVinePhase.Step.HOLD]:
				started = boss.start_vine(action)
				if started: break
	check(started, "Vine sequence started: %s" % String(action))
	driving = true
	await _wait(seconds)
	driving = false
	boss.manual_control = true
	_release()
	_log("take_end")
	await _wait(0.3)

extends "record_master_showcase.gd"
## Reproducible production-action takes. Raw footage and frame ranges stay in temp-assert.
var clips: Array[Dictionary] = []
var lesson_keys: KeyHint
var start_frame := 0

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	output = OS.get_cmdline_user_args()[0]
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
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	lesson_keys = KeyHint.new()
	room.add_child(lesson_keys)
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	lan.dodge_evaded_attack.connect(func(_source: Node2D, _duration: float) -> void: dodges += 1)
	master.attack_hitbox.hit_resolved.connect(_contact)
	running = true
	for id: StringName in [&"sword_wave", &"master_poise_throw"]:
		_reset_take()
		lan.special_attack_cooldown_remaining = 0
		lan.sword_wave_cooldown_remaining = 0
		lan.instant_dash_cooldown_remaining = 0
		master.position.x = 100
		master.set_process(false)
		var labels: Array[String] = []
		match id:
			&"normal_attack": labels = ["J"]
			&"instant_dash": labels = ["U"]
			&"sword_wave": labels = ["H"]
			&"jump_attack": labels = ["W", "J"]
			&"dodge_combo": labels = ["L", "J", "J", "J"]
			&"charged_attack": labels = ["I"]
			&"master_poise_throw": labels = ["E"]
			&"ultimate": labels = ["O"]
		_begin(id, labels)
		await _wait(0.5)
		match id:
			&"normal_attack":
				lan.start_attack_1x(1)
				await _wait(0.5)
				lan.start_attack_2x(1)
				await _wait(0.5)
				lan.start_attack_3x(1)
			&"instant_dash": lan.start_instant_dash(1)
			&"sword_wave": lan.start_sword_wave(1)
			&"jump_attack":
				lan.start_jump()
				await _wait(0.22)
				lan.start_jump_attack_1x(1)
			&"dodge_combo":
				lan.start_back_dodge(-1)
				await _wait(0.25)
				lan.start_dodge_attack_1x(1)
				await _wait(0.45)
				lan.start_dodge_attack_2x(1)
				await _wait(0.45)
				lan.start_dodge_attack_3x(1)
			&"charged_attack":
				Input.action_press(&"special_attack")
				lan.start_special_attack(1)
				await _wait(1.0)
				Input.action_release(&"special_attack")
			&"master_poise_throw":
				master.combat_stats.apply_poise_damage(master.combat_stats.max_poise)
				await _wait(0.4)
				lan.perform_special_attack(1, 0, master)
			&"ultimate":
				lan.combat_stats.add_mana(100)
				lan.start_ultimate_combo()
		await _wait(4.0 if id == &"ultimate" else 2.2)
		while lan.ultimate_active: await process_frame
		_end()
		master.set_process(true)
	for pair in [[&"parry", &"basic_down"], [&"parry_chain", &"return_chain"], [&"red_parry", &"spin_delayed"], [&"gold_dodge", &"air_plunge"]]:
		_reset_take()
		_begin(pair[0], ["L"] if pair[0] == &"gold_dodge" else ["K"])
		await _wait(0.5)
		master.start_clash_rhythm(pair[1])
		driving = true
		var ticks := 0
		while (master.clash_rhythm != null or lan.defense_state != LanPlayer.DefenseState.NONE) and ticks < 600:
			await physics_frame
			ticks += 1
		driving = false
		await _wait(0.8)
		_end()
	_reset_take()
	_begin(&"spirit", [])
	master.charged_power = 0
	master._start_drink()
	while master.state == MasterBoss.State.DRINK: await physics_frame
	await _wait(0.6)
	check(master.phase == 1 and master.charged_power == 1, "First drink demonstrates only the current spirit layer")
	_end()
	if master.phase == 1: master._enter_phase_2()
	while master.state == MasterBoss.State.TRANSFORM: await physics_frame
	_reset_take()
	_begin(&"sobering", ["Q"])
	var save := root.get_node("SaveProgress") as SaveProgressService
	save.add_item(ItemCatalog.HANGOVER_PILL)
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
	master._start_phase_2_howl()
	await _wait(1.0)
	room._on_special_item_use_requested(ItemCatalog.HANGOVER_PILL)
	await _wait(1.4)
	lan.start_attack_1x(1)
	await _wait(1.0)
	_end()
	running = false
	_release_inputs()
	FileAccess.open(output.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify(clips, "\t"))
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	check(clips.size() == 8, "First-form and sobering takes stay separate from second-form skill takes")
	expect_save_untouched()
	finish("COMBAT LESSON RECORDING")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60.0): await process_frame

func _begin(id: StringName, labels: Array) -> void:
	stage = String(id)
	start_frame = Engine.get_process_frames()
	var typed_labels: Array[String] = []
	for label in labels: typed_labels.append(label)
	lesson_keys.configure_labels(lan, typed_labels, 0.36)
	lesson_keys.visible = not labels.is_empty()
	_log("take_start")

func _end() -> void:
	clips.append({"id": stage, "scene": "tutorial", "phase": master.phase, "enemies": ["master"], "start_frame": start_frame, "end_frame": Engine.get_process_frames(), "fps": 60})
	_log("take_end")

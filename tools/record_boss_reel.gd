extends "../tests/support/harness.gd"
## Directed inputs against production actors. All contact, slow motion and damage
## are settled by the game. Placement/reset happens only between labelled takes.
var room: Node2D
var boss
var lan: LanPlayer
var output := ""
var kind := "deer"
var phase_index := 1
var take := ""
var events: Array[Dictionary] = []
var pressed := {}
var release_actions: Array[StringName] = []
var release_keys: Array[int] = []
var driving := false
var bullet := false
var running := false
var parries := 0
var evades := 0
var bullet_attacks := 0
var last_hp := 0
var tick := 0
var caption: Label
var native_boss_position := Vector2.ZERO
var core_side := -1.0
var native_map := ""

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	kind = args[1]
	phase_index = int(args[2]) if args.size() > 2 else 1
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
	if kind == "core":
		native_map = ["res://scenes/levels/chapter_1/chapter_1_wind_boss_room.tscn", "res://scenes/levels/chapter_1/chapter_1_special_boss_upper_right_room.tscn", "res://scenes/levels/chapter_1/chapter_1_special_boss_lower_left_room.tscn", "res://scenes/levels/chapter_1/chapter_1_root_heart_room.tscn"][phase_index]
	assert(kind in ["deer", "core"], "This reel excludes the tutorial frog")
	room = load(native_map).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	lan = room.player
	if kind == "deer":
		if is_instance_valid(room.story.comic): room.story._close_intro()
		boss = room.deer
		boss.manual_control = true
		boss.phase = phase_index
		boss.reset_phase()
	else:
		boss = room.regional_core
		boss.manual_control = true
		boss.set_shield_layers(false, false)
		boss.battle.automatic = false
		boss.battle.random_rings = false
		boss.battle.preview_only = false
		native_boss_position = boss.position
		core_side = -1.0 if boss.position.x > room.room_size.x * 0.5 else 1.0
	lan.input_frozen = false
	paused = false
	boss.set_physics_process(true)
	lan.separation_target = boss
	lan.max_target_separation_x = 1100.0
	var layer := CanvasLayer.new()
	room.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(240, 130)
	caption.size.x = 800
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 23)
	caption.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override(&"shadow_offset_y", 2)
	layer.add_child(caption)
	room._status.hide()
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(func(_r, _a, _p, red):
		parries += 1
		_log("red_parry" if red else "parry"))
	lan.dodge_evaded_attack.connect(func(_source, _duration):
		evades += 1
		_log("bullet_time_started"))
	running = true
	if kind == "deer":
		if phase_index <= 2:
			await _take("快刀接重斩", &"fast_fast_slow", false, 8.0)
			await _take("闪避 · 子弹时间追击", &"light", true, 5.5)
		elif phase_index == 3:
			await _take("穿林五叠", &"deer_phase3_forest_five", false, 7.0)
			await _take("回角逐风", &"deer_phase3_return_four", false, 7.0)
			await _take("踏岳六震", &"deer_phase3_mountain_six", false, 8.0)
			await _take("闪避 · 子弹时间追击", &"deer_phase3_forest_five", true, 7.0)
		else:
			_reset()
			caption.text = "朽角巡林者 · 藤 · 化形"
			boss.start_vine()
			await _wait(5.0)
			await _vine_take(&"pierce_triple", "三连瞬刺 · 红刀反击", 16.0)
	elif kind == "frogger":
		await _take("蛤蟆 · 吐舌接刀", &"tongue", false, 3.0)
		await _take("蛤蟆 · 喷吐接刀", &"spit", false, 3.5)
		await _take("闪避 · 子弹时间追击", &"tongue", true, 5.0)
	else:
		for i in 3:
			await _take("%s · 光圈连震" % ["风区核心", "藤区核心", "雾区核心", "根区核心"][phase_index], &"ring", false, 2.0)
		await _take("闪避光圈 · 子弹时间追击", &"ring", true, 5.0)
	running = false
	_release()
	check(parries > 0, "Production parries landed: %d" % parries)
	if not (kind == "deer" and phase_index == 4):
		check(evades > 0, "Real dodge bullet time: %d" % evades)
		check(bullet_attacks > 0, "Attack states inside bullet time: %d" % bullet_attacks)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("BOSS REEL")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60): await physics_frame

func _reset() -> void:
	driving = false
	_release()
	if kind == "deer": boss.reset_phase()
	elif kind == "frogger": boss._idle()
	else:
		boss.battle.cancel()
		boss.battle.queue_free()
		boss.battle = null
		boss.begin_encounter()
		boss.battle.preview_only = false
	boss.poise_broken = false
	boss.red_parry_hold = false
	boss.combat_stats.restore_health()
	boss.combat_stats.restore_poise()
	if kind == "core":
		boss.position = native_boss_position
		boss.set_shield_layers(false, false)
		lan.reset_after_map_fall(native_boss_position + Vector2(core_side * 170, 0))
	else:
		boss.position = Vector2(1250, 555)
		lan.reset_after_map_fall(Vector2(1080, 555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	lan.facing_direction = -core_side if kind == "core" else 1
	lan.apply_facing_direction()
	if kind == "deer" or kind == "frogger": boss.direction = -1
	pressed.clear()
	last_hp = lan.combat_stats.health

func _take(label: String, action: StringName, use_dodge: bool, seconds: float) -> void:
	_reset()
	take = String(action) + ("_dodge" if use_dodge else "")
	caption.text = ("朽角巡林者 · %s · " % DeerBoss.PHASE_NAMES[phase_index-1] if kind == "deer" else "") + label
	_log("take_start")
	await _wait(0.5)
	bullet = use_dodge
	if kind == "deer":
		if phase_index == 3: boss.start_clash(action, lan.position.x)
		elif action == &"light": boss.start_attack(DeerBoss.State.LIGHT)
		else: boss.start_combo(action)
	elif kind == "frogger": boss.start_action(action, lan.position)
	else: boss.battle.spawn_normal_ring()
	driving = true
	await _wait(seconds)
	driving = false
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_left")
	_log("take_end")

func _vine_take(action: StringName, label: String, seconds: float) -> void:
	take = String(action)
	caption.text = "朽角巡林者 · 藤 · " + label
	pressed.clear()
	bullet = false
	boss.start_vine(action)
	driving = true
	_log("take_start")
	await _wait(seconds)
	driving = false
	_log("take_end")

func _physics_process(_delta: float) -> bool:
	if not running: return false
	tick += 1
	for action in release_actions: Input.action_release(action)
	release_actions.clear()
	for code in release_keys: _key(code, false)
	release_keys.clear()
	if lan.combat_stats.health < last_hp: _log("hurt")
	last_hp = lan.combat_stats.health
	if not driving: return false
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_left")
	if lan.dodge_bullet_time_remaining > 0:
		var gap: float = boss.position.x - lan.position.x
		var move: StringName = &"ui_right" if gap > 0 else &"ui_left"
		Input.action_release(&"ui_left" if gap > 0 else &"ui_right")
		Input.action_press(move)
		if tick % 10 == 0:
			_key(KEY_J, true)
			release_keys.append(KEY_J)
		if lan.attack_state != LanPlayer.AttackState.NONE:
			bullet_attacks += 1
			if bullet_attacks == 1: _log("bullet_time_attack")
		return false
	if kind == "deer": _drive_deer()
	elif kind == "frogger":
		var target := 0.2 if boss.action == &"tongue" else 0.7
		_input_at(target-boss.action_time, boss.action, bullet)
	else:
		for hazard in boss.battle.hazards:
			if not hazard is RegionalCoreRing or hazard.finished: continue
			var distance: float = hazard.global_position.distance_to(lan.global_position+Vector2(0,-42))
			var contact: float = RegionalCoreRing.WARNING + maxf(0,distance-40)/RegionalCoreRing.SPEED
			_input_at(contact-hazard.age, hazard.get_instance_id(), bullet)
	return false

func _drive_deer() -> void:
	var deer: DeerBoss = boss
	if phase_index <= 2:
		if deer.state == DeerBoss.State.LIGHT:
			_input_at((0.583333/deer._action_speed)-deer._time, "light_%d" % deer.combo_step, bullet)
		elif deer.state == DeerBoss.State.HEAVY:
			_input_at((1.4+deer._heavy_hold)/deer._action_speed-deer._time, "heavy_%d" % deer.combo_step, bullet)
	elif phase_index == 3 and deer.state == DeerBoss.State.CLASH:
		var contact := deer.clash_phase.next_parry_contact_in()
		var resolved := 0
		if is_instance_valid(deer.clash_phase.authored):
			for row: Dictionary in deer.clash_phase.authored.rows:
				if row.started: resolved += 1
		if contact >= 0: _input_at(contact, "%d_%d_%d" % [deer.clash_phase.combo_serial, deer.clash_phase.step_index, resolved], bullet)
		var gap := deer.position.x-lan.position.x
		if not bullet and absf(gap) > 160:
			Input.action_press(&"ui_right" if gap > 0 else &"ui_left")
		else: Input.action_release(&"ui_right")
	elif phase_index == 4:
		if deer.vine_phase.step == DeerVinePhase.Step.STAGGER:
			var gap: float = deer.position.x-lan.position.x
			Input.action_release(&"ui_left" if gap > 0 else &"ui_right")
			Input.action_press(&"ui_right" if gap > 0 else &"ui_left")
			if tick % 10 == 0:
				_key(KEY_J, true)
				release_keys.append(KEY_J)
			return
		Input.action_release(&"ui_right")
		Input.action_release(&"ui_left")
		for strike in deer.vine_phase.strikes:
			if not is_instance_valid(strike) or strike.snapped or strike.finished: continue
			var contact: float = strike.warn
			if strike.kind in [&"pierce", &"pierce_red"]: contact += 0.15
			_input_at(contact-strike._age, strike.get_instance_id(), false)

func _input_at(left: float, id: Variant, dodge: bool) -> void:
	if left < 0 or left > (0.045 if dodge else 0.20) or pressed.has(id): return
	pressed[id] = true
	if dodge:
		_key(KEY_L, true)
		release_keys.append(KEY_L)
		_log("dodge_input")
	else:
		Input.action_press(&"parry")
		release_actions.append(&"parry")
		_log("parry_input")

func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _release() -> void:
	for action in [&"ui_left", &"ui_right", &"parry"]: Input.action_release(action)
	for code in [KEY_J, KEY_L]: _key(code, false)
	release_keys.clear()
	release_actions.clear()

func _log(event: String) -> void:
	var frame := Engine.get_process_frames()
	events.append({"map":native_map,"event":event,"take":take,"frame":frame,"video_t":float(frame)/60,"hp":lan.combat_stats.health,"bullet_time":lan.dodge_bullet_time_remaining,"attack":lan.attack_state,"lan":str(lan.position),"boss":str(boss.position),"frozen":lan.input_frozen,"defense":lan.defense_state})
	if event in ["parry", "red_parry", "bullet_time_attack"] and DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(func(): root.get_texture().get_image().save_png(output.path_join("%s_%04d.png" % [event,frame])), CONNECT_ONE_SHOT)

extends "../tests/support/harness.gd"
## Directed production-room takes. Only button presses drive Lan; hits/parries/counters
## settle through production collision and feedback. Each take resets between clips.

const IDS := [&"basic_down", &"return_chain", &"inertia_combo", &"lunge_combo", &"air_qi_combo"]
const TITLES := ["一斩 · 首刀蓝光 · 看准震刀", "回身三连 · 稳拍接刀", "重剑惯性连斩 · 动作样板", "原稿突进 · 动作样板", "跃空剑气 · 动作样板"]
var room: Node2D
var master: MasterBoss
var lan: LanPlayer
var output := ""
var caption: Label
var running := false
var driving := false
var stage := ""
var elapsed := 0.0
var pressed: Dictionary = {}
var release_actions: Array[StringName] = []
var release_keys: Array[int] = []
var events: Array[Dictionary] = []
var total_parries := 0
var red_parries := 0
var dodges := 0
var damage_taken := 0
var last_health := 0
var cue_captured := false
var phase2_action: StringName = &""
var move_action: StringName = &""

func run() -> void:
	# The production camera pulls out on the dive. Use black letterbox margins
	# for this recording instead of the editor's grey clear colour.
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
		check([1, 3, -1, -1, -1][i] < 0 or total_parries - before == [1, 3, -1, -1, -1][i], "%s: real parry count %d" % [stage, total_parries-before])
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
	running = false
	_release_inputs()
	check(cue_captured, "First blade cue is rendered and captured")
	check(damage_taken == 0, "No health loss during the directed takes (%d)" % damage_taken)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("MASTER SHOWCASE")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60.0): await physics_frame

func _reset_take() -> void:
	driving = false
	_release_inputs()
	Engine.time_scale = 1.0
	master._interrupt_for_special(0.0)
	master.poise_broken = false
	master.red_parry_hold = false
	master.combat_stats.restore_health()
	master.combat_stats.restore_poise()
	master.position = Vector2(140, 555)
	master.movement_direction = -1.0
	master.apply_facing_direction()
	if master.phase == 1:
		master.play_idle()
	else:
		master._enter_phase_2_idle(1.0)
	lan.reset_after_map_fall(Vector2(-10, 555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	last_health = lan.combat_stats.health
	lan.parry_chain.cancel()
	lan.facing_direction = 1.0
	lan.apply_facing_direction()
	pressed.clear()

func _physics_process(delta: float) -> bool:
	if not running: return false
	elapsed += delta
	for action in release_actions: Input.action_release(action)
	release_actions.clear()
	for key in release_keys: _key(key, false)
	release_keys.clear()
	if lan.combat_stats.health < last_health:
		damage_taken += last_health - lan.combat_stats.health
		_log("hurt")
	last_health = lan.combat_stats.health
	if not driving: return false
	if master.clash_rhythm != null:
		_drive_rhythm(master.clash_rhythm)
	elif phase2_action != &"" and master.state == MasterBoss.State.PHASE_2_ATTACK:
		var frame := float(master.animated_sprite.frame) + master.animated_sprite.frame_progress
		var left := (6.0 - frame) / float(master.animated_sprite.sprite_frames.get_animation_speed(phase2_action))
		if left >= 0.0 and left <= 0.20 and not pressed.has("phase2_red"):
			pressed["phase2_red"] = true
			_press(&"parry")
	if not cue_captured and stage == "basic_down" and lan.parry_cue.time_to_contact <= 0.30 and lan.parry_cue.should_show():
		lan.parry_cue._process(0.0)
		if lan.parry_cue._display.is_visible_in_tree():
			cue_captured = true
			_snapshot("first_blade_cue")
	return false

func _drive_rhythm(r: MasterClashRhythm) -> void:
	for i in r.strikes.size():
		var strike := r.strikes[i]
		var left := float(strike.t) - r.elapsed
		if strike.done or left < 0.0 or pressed.has(i): continue
		if strike.danger == &"gold":
			if left <= 0.14:
				pressed[i] = true
				_dodge_near_master()
		elif left <= 0.20:
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
			# Parry-success recovery cannot be dodge-cancelled. Evade these qi
			# rather than forcing a cancel before the unavoidable gold landing.
			_dodge_near_master()
	# Re-approach between grounded contacts using movement input, without teleporting.
	var gap := master.position.x - lan.position.x
	if not r.data.get("air", false) and not r.data.get("blink", false) and absf(gap) > 155.0:
		_set_move(&"ui_right" if gap > 0.0 else &"ui_left")
	else:
		_stop_move()

func _dodge_near_master() -> void:
	# Alternate inward/outward so repeated dodges keep the fight in camera range.
	var gap := master.position.x - lan.position.x
	var direction := signf(gap) if absf(gap) > 360.0 else -signf(gap)
	var action: StringName = &"ui_right" if direction > 0.0 else &"ui_left"
	Input.action_press(action)
	release_actions.append(action)
	_key(KEY_L, true)
	release_keys.append(KEY_L)
	_log("dodge_press")

func _set_move(action: StringName) -> void:
	if move_action == action: return
	_stop_move()
	move_action = action
	Input.action_press(action)

func _stop_move() -> void:
	if move_action != &"": Input.action_release(move_action)
	move_action = &""

func _press(action: StringName) -> void:
	Input.action_press(action)
	release_actions.append(action)
	_log("press_" + String(action))

func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _release_inputs() -> void:
	_stop_move()
	for action in [&"parry", &"interact", &"special_attack", &"ui_left", &"ui_right"]: Input.action_release(action)
	_key(KEY_L, false)
	release_actions.clear()
	release_keys.clear()

func _parry(receiver: DamageReceiver2D, _attack: CombatAttackData, _point: Vector2, red: bool) -> void:
	if receiver != master: return
	total_parries += 1
	if red: red_parries += 1
	_log("red_parry" if red else "parry")
	if red: _snapshot("red_counter_" + stage)

func _contact(_target: Node, result: CombatHitResult.Type) -> void:
	_log(CombatHitResult.Type.keys()[result])

func _log(event: String) -> void:
	events.append({"event": event, "take": stage, "frame": Engine.get_process_frames(), "t": elapsed, "hp": lan.combat_stats.health, "defense": lan.defense_state, "ground": lan.ground_action_state, "dodge_key": Input.is_physical_key_pressed(KEY_L), "dodge_buffer": lan.dodge_input_buffer_remaining})

func _snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	RenderingServer.frame_post_draw.connect(func() -> void:
		root.get_texture().get_image().save_png(output.path_join(label + ".png")), CONNECT_ONE_SHOT)

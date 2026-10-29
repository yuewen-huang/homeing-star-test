extends "../tests/support/harness.gd"
## Priority Master phase-2 ultra-fast combo chain: buffed pressure_five + chase_five.
## PHASE_2_BUFF makes body combos run at 1.4x — the "超快连段" peak.
## White = parry; red/gold = dodge (red_parry would cancel the chain).

const PARRY_LEAD := 0.16
const PARRY_MIN := 0.02
const DODGE_LEAD := 0.16
const IDS: Array[StringName] = [&"master_phase2_pressure_five", &"master_phase2_pressure_five"]
const TITLES: Array[String] = ["二阶段 · 超快五连压迫", "二阶段 · 超快五连压迫（复拍）"]
const EXPECTED: Array[int] = [3, 3]

var room: Node2D
var master: MasterBoss
var lan: LanPlayer
var output := ""
var caption: Label
var running := false
var driving := false
var stage := ""
var elapsed := 0.0
var release_actions: Array[StringName] = []
var release_keys: Array[int] = []
var events: Array[Dictionary] = []
var total_parries := 0
var dodges := 0
var contacts_seen := 0
var damage_taken := 0
var last_health := 0
var pressed: Dictionary = {}
var dodge_flip := false

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://master_p2_priority"
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
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	lan.dodge_evaded_attack.connect(func(source: Node2D, _duration: float) -> void:
		if source == master:
			dodges += 1
			_log("evade"))
	master._enter_phase_2()
	while master.state == MasterBoss.State.TRANSFORM:
		await physics_frame
	await _wait(0.4)
	running = true
	for i in IDS.size():
		_reset_take()
		stage = String(IDS[i])
		caption.text = "优先高燃 · 二阶段狂化加速 · 无敌关闭\n" + TITLES[i]
		_log("take_start")
		await _wait(0.5)
		var before := total_parries
		var hp_before := lan.combat_stats.health
		var face := 1.0 if i == 0 else -1.0
		master.position = Vector2(640, 555)
		master.movement_direction = face
		master.apply_facing_direction()
		lan.reset_after_map_fall(Vector2(master.position.x + face * 160.0, 555))
		lan.facing_direction = -face
		lan.apply_facing_direction()
		await physics_frame
		master.phase_2_buff_remaining = master.PHASE_2_BUFF_DURATION
		master.phase_2_finale_active = false
		master.phase_2_howl_cooldown_remaining = 100.0
		master.manual_control = false
		pressed.clear()
		master._face_phase_2_target(lan.position.x - master.position.x)
		check(master.start_phase_2_body_action(IDS[i]), "%s starts" % stage)
		driving = true
		var ticks := 0
		while (master.state == MasterBoss.State.PHASE_2_BODY_ACTION or master.parry_pause_remaining > 0.0 or lan.defense_state != LanPlayer.DefenseState.NONE or lan.dodge_bullet_time_remaining > 0.0) and ticks < 1400:
			await physics_frame
			ticks += 1
		driving = false
		master.manual_control = true
		_release_inputs()
		var got := total_parries - before
		check(got >= EXPECTED[i], "%s parries %d (want >= %d, dodges %d)" % [stage, got, EXPECTED[i], dodges])
		check(lan.combat_stats.health == hp_before, "%s no damage (%d)" % [stage, lan.combat_stats.health])
		await _wait(0.6)
		_log("take_end")
	running = false
	_release_inputs()
	check(damage_taken == 0, "No health loss across p2 priority (%d)" % damage_taken)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("MASTER P2 PRIORITY")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await physics_frame

func _reset_take() -> void:
	_release_inputs()
	driving = false
	pressed.clear()
	Engine.time_scale = 1.0
	master.red_parry_hold = false
	master.parry_pause_remaining = 0.0
	master._interrupt_for_special(0.0)
	master.combat_stats.restore_poise()
	master.poise_broken = false
	master.phase_2_finale_active = false
	master._enter_phase_2_idle(1.0)
	lan.parry_chain.cancel()
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.finish_defense()
	last_health = lan.combat_stats.health

func _physics_process(delta: float) -> bool:
	if not running:
		return false
	elapsed += delta
	for action in release_actions:
		Input.action_release(action)
	release_actions.clear()
	for code in release_keys:
		_key(code, false)
	release_keys.clear()
	if lan.combat_stats.health < last_health:
		damage_taken += last_health - lan.combat_stats.health
		_log("hurt")
	last_health = lan.combat_stats.health
	if master.state == MasterBoss.State.PHASE_2_IDLE:
		master.phase_2_idle_remaining = 100.0
	if not driving:
		return false
	if master.state != MasterBoss.State.PHASE_2_BODY_ACTION:
		return false
	_drive_body()
	return false

func _drive_body() -> void:
	var action := master.phase_2_body_action
	if action == null or not action.active:
		return
	if action.vfx != null:
		for row in action.vfx.ground_cues():
			var left_g: float = float(row.release) - action.elapsed
			var gkey := "g_%s" % str(row.get("key", row.release))
			if left_g >= 0.0 and left_g <= 0.35 and not pressed.has(gkey):
				pressed[gkey] = true
				Input.action_press(&"jump")
				release_actions.append(&"jump")
				_log("jump_ground")
	var gap := master.position.x - lan.position.x
	if absf(gap) > 110.0 and lan.defense_state == LanPlayer.DefenseState.NONE and lan.dodge_bullet_time_remaining <= 0.0:
		var move: StringName = &"ui_right" if gap > 0.0 else &"ui_left"
		Input.action_press(move)
		release_actions.append(move)
	var threats: Array[Dictionary] = []
	var at := 0.0
	for i in action.data.clips.size():
		var clip: Dictionary = action.data.clips[i]
		for gi in clip.groups.size():
			var group: Dictionary = clip.groups[gi]
			var contact := float(group.get("contact", group.members[0].release))
			var abs_t: float = at + contact - float(clip.start_time)
			var danger: CombatAttackData.DangerType = action._danger(clip, group)
			threats.append({"abs": abs_t, "danger": danger, "key": "%d_%d" % [i, gi]})
		at += float(clip.duration)
	for row in threats:
		var left: float = float(row.abs) - action.elapsed
		if left < -0.05 or left > 0.30:
			continue
		var danger: CombatAttackData.DangerType = row.danger
		if danger != CombatAttackData.DangerType.NORMAL:
			if left <= DODGE_LEAD and left >= 0.0 and not pressed.has(row.key):
				pressed[row.key] = true
				_dodge_away()
				_log("dodge_input_%s" % ("gold" if danger == CombatAttackData.DangerType.UNPARRYABLE_DANGER else "red"))
		else:
			# Retry parry every frame in window until success or window closes —
			# first try may be eaten while Lan is still in dodge recovery.
			if left <= PARRY_LEAD and left >= PARRY_MIN:
				if lan.defense_state == LanPlayer.DefenseState.NONE and lan.dodge_bullet_time_remaining <= 0.0:
					Input.action_press(&"parry")
					release_actions.append(&"parry")
					if not pressed.has(str(row.key) + "_logged"):
						pressed[str(row.key) + "_logged"] = true
						_log("parry_input")
			elif left < PARRY_MIN:
				pressed[row.key] = true

func _dodge_away() -> void:
	var gap := master.position.x - lan.position.x
	# Step outward (away from boss) so the active blade misses, then approach resumes.
	var away := -signf(gap)
	if away == 0.0:
		away = -1.0
	var move: StringName = &"ui_right" if away > 0.0 else &"ui_left"
	Input.action_press(move)
	release_actions.append(move)
	_key(KEY_L, true)
	release_keys.append(KEY_L)

func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _release_inputs() -> void:
	for action in [&"parry", &"interact", &"special_attack", &"ui_left", &"ui_right", &"jump"]:
		Input.action_release(action)
	_key(KEY_L, false)
	release_actions.clear()
	release_keys.clear()

func _parry(_receiver: DamageReceiver2D, _attack: CombatAttackData, _point: Vector2, red: bool) -> void:
	total_parries += 1
	_log("red_parry" if red else "parry")

func _log(event: String) -> void:
	events.append({
		"event": event,
		"take": stage,
		"frame": Engine.get_process_frames(),
		"t": elapsed,
		"hp": lan.combat_stats.health if lan else 0,
		"defense": lan.defense_state if lan else -1,
		"cue": lan.parry_cue.time_to_contact if lan else -1.0,
	})


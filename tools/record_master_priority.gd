extends "../tests/support/harness.gd"
## Priority high-energy Master takes: 崩山击 / 闸斩 / 断头台 (mountain, combo_four, combo_five).
## NORMAL difficulty so continuous assist covers later cuts after the first manual press.
## Real Input.action_press only; MovieWriter-friendly (--write-movie / --fixed-fps 60).

## Feel-tuned: press inside a tight window; one arm per swing (cue INF -> armed).
const PARRY_LEAD := 0.16
const PARRY_MIN := 0.02
const IDS: Array[StringName] = [&"mountain", &"combo_four", &"combo_five"]
const TITLES: Array[String] = ["崩山击 · 月牙剑气", "四刀连招 · 巨刃闸斩", "五刀连招 · 断头台重坠"]
const EXPECTED: Array[int] = [2, 4, 5]

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
var events: Array[Dictionary] = []
var total_parries := 0
var contacts_seen := 0
var damage_taken := 0
var last_health := 0
var move_action: StringName = &""
var cue_armed := true

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://master_priority"
	DirAccess.make_dir_recursive_absolute(output)
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true  # suppress AI during room boot
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
	master.attack_hitbox.hit_resolved.connect(_contact)
	running = true
	for i in IDS.size():
		_reset_take()
		stage = String(IDS[i])
		move_action = IDS[i]
		caption.text = "优先高燃 · 普通难度 · 无敌关闭\n" + TITLES[i]
		_log("take_start")
		await _wait(0.6)
		var before := total_parries
		var contacts_before := contacts_seen
		var hp_before := lan.combat_stats.health
		# Production approach distance (tests prove blades reach here; combo target_distance 115 is AI spacing only).
		master.position = Vector2(640, 555)
		master.movement_direction = 1.0
		master.apply_facing_direction()
		lan.reset_after_map_fall(Vector2(master.position.x + master.ATTACK_APPROACH_DISTANCE, 555))
		lan.facing_direction = -1.0
		lan.apply_facing_direction()
		await physics_frame
		cue_armed = true
		pressed.clear()
		# Phase-1 blade resolve is skipped while manual_control (dev preview). Combat needs it off.
		master.manual_control = false
		check(master.start_phase_1_action(IDS[i]), "%s starts" % stage)
		driving = true
		var ticks := 0
		while master.state == MasterBoss.State.PHASE_1_ACTION and ticks < 900:
			await physics_frame
			ticks += 1
		var settle := 0
		while settle < 90 and (master.state == MasterBoss.State.PHASE_1_ACTION or master.parry_pause_remaining > 0.0 or lan.defense_state != LanPlayer.DefenseState.NONE):
			await physics_frame
			settle += 1
		driving = false
		move_action = &""
		master.manual_control = true
		_release_inputs()
		var got := total_parries - before
		var hit := contacts_seen - contacts_before
		check(got >= EXPECTED[i], "%s parries %d (want >= %d, contacts %d)" % [stage, got, EXPECTED[i], hit])
		check(lan.combat_stats.health == hp_before, "%s no damage (%d)" % [stage, lan.combat_stats.health])
		await _wait(0.7)
		_log("take_end")
	running = false
	_release_inputs()
	check(damage_taken == 0, "No health loss across priority takes (%d)" % damage_taken)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("MASTER PRIORITY")

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await physics_frame

func _reset_take() -> void:
	_release_inputs()
	pressed.clear()
	driving = false
	move_action = &""
	cue_armed = true
	Engine.time_scale = 1.0
	master.red_parry_hold = false
	master.parry_pause_remaining = 0.0
	master._interrupt_for_special(0.0)
	master.combat_stats.restore_poise()
	master.poise_broken = false
	if master.phase == 1:
		master.play_idle()
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
	if lan.combat_stats.health < last_health:
		damage_taken += last_health - lan.combat_stats.health
		_log("hurt")
	last_health = lan.combat_stats.health
	if not driving:
		return false
	if move_action == &"" or master.state != MasterBoss.State.PHASE_1_ACTION:
		return false
	var cue := lan.parry_cue.time_to_contact
	# Re-arm when the cue clears (gap between cuts / INF).
	if cue < 0.0 or cue > 1.0:
		cue_armed = true
		return false
	if cue_armed and cue <= PARRY_LEAD and cue >= PARRY_MIN:
		cue_armed = false
		Input.action_press(&"parry")
		release_actions.append(&"parry")
		_log("parry_input")
	return false

func _release_inputs() -> void:
	for action in [&"parry", &"interact", &"special_attack", &"ui_left", &"ui_right"]:
		Input.action_release(action)
	release_actions.clear()

func _parry(_receiver: DamageReceiver2D, _attack: CombatAttackData, _point: Vector2, red: bool) -> void:
	total_parries += 1
	_log("red_parry" if red else "parry")

func _contact(_target: Node, result: CombatHitResult.Type) -> void:
	contacts_seen += 1
	_log("contact_%s" % CombatHitResult.Type.keys()[result])

func _log(event: String) -> void:
	events.append({
		"event": event,
		"take": stage,
		"frame": Engine.get_process_frames(),
		"t": elapsed,
		"hp": lan.combat_stats.health if lan else 0,
		"defense": lan.defense_state if lan else -1,
		"cue": lan.parry_cue.time_to_contact if lan else -1.0,
		"gap": (lan.position.x - master.position.x) if (lan and master) else 0.0,
	})

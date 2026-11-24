extends "../../support/harness.gd"

const TRIPLE := MasterPhase2BodyAction.TRIPLE_CLAW
const FIVE := MasterPhase2BodyAction.PRESSURE_FIVE
const NORMAL := CombatAttackData.DangerType.NORMAL
const RED := CombatAttackData.DangerType.COUNTERABLE_DANGER
const GOLD := CombatAttackData.DangerType.UNPARRYABLE_DANGER

var room: Node2D
var boss: MasterBoss
var lan: LanPlayer
var assist: BattleAssistSettingsService
var parries := 0
var red_counters := 0
var dodges := 0
var boss_hits := 0


func run() -> void:
	setup_room()

	var args := OS.get_cmdline_user_args()
	var record_dir := args[0] if not args.is_empty() else ""
	var first_frame := Engine.get_process_frames()
	var shared_groups: Array = []
	for id in [TRIPLE, FIVE]:
		prepare(BattleAssistSettingsService.Difficulty.NORMAL)
		await wait_frames(20)
		boss.start_phase_2_body_action(id)
		var action := boss.phase_2_body_action
		var triple: Dictionary = action.data.clips[0 if id == TRIPLE else 1]
		if id == TRIPLE:
			shared_groups = triple.groups.duplicate(true)
		else:
			check(triple.groups == shared_groups, "Cross-claw contact, samples and timing are identical in both moves")
		var expected := [NORMAL, RED, GOLD] if id == TRIPLE else [NORMAL, NORMAL, RED, GOLD, NORMAL]
		var speed := boss.get_phase_2_attack_speed()
		check(is_equal_approx(speed, 1.76), "%s uses four stacks plus the circle" % id)
		check(action._attack_groups.map(func(beat: Dictionary) -> int: return beat.danger) == expected,
			"%s uses the authored ordinary, red and gold attack order" % id)
		var gold: Dictionary = action._attack_groups[expected.find(GOLD)]
		check((float(gold.release) - action._gold_prepare_at) / speed >= .25,
			"Raised claws give at least 250 ms of preparation at maximum attack speed")
		await defend(action, false, true)
		check(lan.combat_stats.health == lan.combat_stats.max_health and dodges == 1,
			"Launched gold claw requires and rewards an actual dodge")
		check(parries == expected.size() - 1 and red_counters == 0,
			"Assist catches the red claw normally and the near-five uppercut remains a separate defense")
		check(is_equal_approx(boss.phase_2_idle_remaining, .85 if id == TRIPLE else 1.2),
			"The grounded pose starts the full punish window")
		await punish(id == FIVE)
		check(boss_hits == (1 if id == TRIPLE else 2), "Close-range J inputs land inside the opening")
		await wait_frames(10)

	if not record_dir.is_empty():
		var clip := {"id": "phase_2_combo", "scene": "tutorial", "phase": 2, "enemies": ["master"],
			"difficulty": "normal", "attack_speed": 1.76, "no_damage": failures == 0,
			"parries": 6, "red_parries": 0, "dodges": 2, "punish_hits": [1, 2],
			"start_frame": first_frame, "end_frame": Engine.get_process_frames(), "fps": 60}
		FileAccess.open(record_dir.path_join("clips.json"), FileAccess.WRITE).store_string(JSON.stringify([clip], "\t"))
		FileAccess.open(record_dir.path_join("events.json"), FileAccess.WRITE).store_string("[]")
	else:
		await check_counter_and_failed_defense()
		await check_uppercut_wave()
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER PHASE TWO READABILITY")


func setup_room() -> void:
	use_memory_progress()
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	boss = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	assist = root.get_node("BattleAssist")
	boss.voice.stop()
	boss._enter_phase_2()
	boss._enter_phase_2_idle(100.0)
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.parry_landed.connect(_on_parry)
	lan.dodge_evaded_attack.connect(func(source: Node2D, _duration: float) -> void:
		if source == boss: dodges += 1)
	boss.combat_stats.health_changed.connect(func(_hp: int, _max_hp: int) -> void:
		if boss.has_phase_2_punish_window(): boss_hits += 1)


func prepare(difficulty: BattleAssistSettingsService.Difficulty) -> void:
	assist.set_difficulty(difficulty)
	boss._enter_phase_2_idle(100.0)
	boss.position = Vector2(235, 555)
	boss.movement_direction = -1
	boss.action_clock.clear()
	boss.charged_power = 4
	boss.phase_2_buff_remaining = 8.0
	boss.phase_2_magic_circle.show()
	boss.phase_2_magic_circle.play(&"howl")
	lan.reset_after_map_fall(boss.position + Vector2(-110, 0))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(100)
	lan.facing_direction = 1
	lan.apply_facing_direction()
	lan.parry_chain.cancel()
	parries = 0
	dodges = 0
	red_counters = 0
	boss_hits = 0


func defend(action: MasterPhase2BodyAction, hand_parry_red: bool, evade_gold: bool) -> void:
	var speed := boss.get_phase_2_attack_speed()
	for beat in action._attack_groups:
		if beat.danger == RED and not hand_parry_red:
			continue
		var evading: bool = beat.danger == GOLD and evade_gold
		var before_release := .01 if evading else .14
		while boss.phase_2_body_action != null and boss.phase_2_body_action == action \
				and (float(beat.release) - action.elapsed) / speed > before_release:
			await physics_frame
		if boss.phase_2_body_action == null or boss.phase_2_body_action != action:
			break
		if evading:
			key(KEY_L, true)
		else:
			Input.action_press(&"parry")
		await physics_frame
		key(KEY_L, false)
		Input.action_release(&"parry")
		if evading:
			Input.action_press(&"ui_right")
	while boss.phase_2_body_action != null and boss.phase_2_body_action == action:
		await physics_frame
	Input.action_release(&"ui_right")


func punish(follow_up: bool) -> void:
	var turn := KEY_A if lan.position.x > boss.position.x else KEY_D
	key(turn, true)
	await wait_frames(4)
	key(KEY_J, true)
	await wait_frames(3)
	key(KEY_J, false)
	key(turn, false)
	if follow_up:
		await wait_frames(12)
		key(turn, true)
		key(KEY_J, true)
		await wait_frames(3)
		key(KEY_J, false)
		key(turn, false)
	await wait_frames(34)


func check_counter_and_failed_defense() -> void:
	prepare(BattleAssistSettingsService.Difficulty.HARD)
	await wait_frames(20)
	boss.start_phase_2_body_action(FIVE)
	await defend(boss.phase_2_body_action, true, false)
	check(red_counters == 1 and boss.phase_2_body_action == null and dodges == 0,
		"Manual red parry cuts the five-hit action before it turns gold")

	await wait_frames(65)
	prepare(BattleAssistSettingsService.Difficulty.NORMAL)
	await wait_frames(20)
	boss.start_phase_2_body_action(TRIPLE)
	await defend(boss.phase_2_body_action, false, false)
	check(lan.combat_stats.health == lan.combat_stats.max_health - lan.pulse_duel.HEAVY_DAMAGE,
		"K alone takes the gold finisher's heavy damage in the formal duel")

	prepare(BattleAssistSettingsService.Difficulty.NORMAL)
	boss.start_phase_2_body_action(FIVE)
	var action := boss.phase_2_body_action
	check(boss.use_sobering_item() and boss.phase_2_body_action == action
		and is_equal_approx(boss.get_phase_2_attack_speed(), 1.4),
		"Sobering lowers the rate without interrupting five or removing the circle")
	action.advance(float(action.data.duration))
	check(is_equal_approx(boss.phase_2_idle_remaining, 1.5), "A sober near five gives the existing low-stack window")


func check_uppercut_wave() -> void:
	prepare(BattleAssistSettingsService.Difficulty.HARD)
	boss._start_phase_2_attack(&"phase_2_uppercut")
	boss.animated_sprite.frame = 5
	var torso := lan.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	lan.global_position += boss.attack_collision_shape.global_position - torso.global_position
	lan.start_parry()
	check(boss.attack_hitbox.resolve_nearby_parries() and not boss.red_parry_hold, "Uppercut takes an ordinary parry")
	for frame in 90:
		await physics_frame
		if boss.phase_2_wave_launched: break
	check(room.get_children().any(func(node: Node): return node is MasterGroundWave), "Parried uppercut still releases its ground wave")


func _on_parry(source: DamageReceiver2D, _attack: CombatAttackData, _at: Vector2, red: bool) -> void:
	if source != boss: return
	parries += 1
	if red: red_counters += 1


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

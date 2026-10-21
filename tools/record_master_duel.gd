extends "record_master_showcase.gd"
## Continuous directed duel: production attacks and real player input, no state resets
## after the opening placement. No recorder captions. Memory-only inventory/progress.
var p2_track: StringName = &""
var throws := 0
var ultimates := 0
var sober_uses := 0
var drink_layers := 0
var first_health := 0

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://master_duel"
	DirAccess.make_dir_recursive_absolute(output)
	var save := use_memory_progress()
	save.add_item(ItemCatalog.HANGOVER_PILL)
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
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
	master.charged_power_changed.connect(func(current: int, _maximum: int) -> void:
		drink_layers = current
		_log("drink_layer_%d" % current)
		_snapshot("drink_layer_%d" % current))
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_parry)
	lan.dodge_evaded_attack.connect(func(source: Node2D, _duration: float) -> void:
		if source == master:
			dodges += 1
			_log("evade"))
	master.attack_hitbox.hit_resolved.connect(_contact)
	_reset_take() # The only reset: before the first recorded exchange.
	first_health = lan.combat_stats.health
	running = true
	await _wait(0.35)
	var routes := [&"basic_down", &"return_chain", &"inertia_combo", &"lunge_combo", &"air_qi_combo", &"return_chain", &"inertia_combo", &"air_qi_combo"]
	for id: StringName in routes:
		if master.phase != 1: break
		await _rhythm_take(id)
		await _punish_break()
	for i in 5:
		if master.phase != 1: break
		await _rhythm_take(&"air_qi_combo")
	check(master.phase == 2, "Continuous duel reaches phase two through real drinks")
	while master.state == MasterBoss.State.TRANSFORM: await physics_frame
	_log("phase_2_ready")
	await _wait(0.25)
	await _phase2(&"phase_2_attack_2")
	await _punish_break()
	await _phase2(&"phase_2_dash")
	await _punish_break()
	stage = "sobering"
	_log("take_start")
	master._start_phase_2_howl()
	await _wait(0.9)
	room._sobering_notice.show_hint("Q 使用醒酒丸 · 解除红色酒气")
	await _wait(0.65)
	_press(&"special_item_use")
	await _wait(0.15)
	room._sobering_notice.hide_hint()
	if master.sobering_remaining > 0.0:
		sober_uses += 1
		_log("sobering_success")
		_snapshot("sobering_success")
	await _counter()
	await _ultimate()
	_log("take_end")
	for i in 8:
		if master.combat_stats.health <= 0: break
		await _phase2(&"phase_2_attack_2")
		await _punish_break()
		if master.combat_stats.health <= 0: break
		await _phase2(&"phase_2_dash")
		await _punish_break()
		if master.combat_stats.health <= 0: break
		await _counter()
		if i % 2 == 1: await _ultimate()
	await _wait(0.4)
	driving = false
	running = false
	_release_inputs()
	check(cue_captured, "Opening blue cue actually rendered")
	check(drink_layers == 4, "Four real drinks accumulate blue spirit")
	check(total_parries >= 10 and red_parries >= 2, "Real chained parries and red counters")
	check(throws > 0, "Broken-poise throw entered through E input")
	check(sober_uses == 1, "Real Q input clears the red spirit")
	check(ultimates > 0, "Real O inputs start an ultimate")
	check(master.combat_stats.health <= 0, "Real damage defeats phase two")
	check(damage_taken == 0, "No health lost during the continuous duel (%d)" % damage_taken)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("MASTER DUEL")

func _idle_player() -> void:
	var ticks := 0
	while (not lan.can_start_parry() or lan.ultimate_active) and master.combat_stats.health > 0 and ticks < 800:
		await physics_frame
		ticks += 1

func _approach(gap: float) -> void:
	await _idle_player()
	var ticks := 0
	while absf(master.position.x-lan.position.x) > gap and ticks < 240:
		_set_move(&"ui_right" if master.position.x > lan.position.x else &"ui_left")
		await physics_frame
		ticks += 1
	_stop_move()
	# A brief legal direction input faces the target even after a counter crossed it.
	_set_move(&"ui_right" if master.position.x > lan.position.x else &"ui_left")
	await physics_frame
	_stop_move()

func _rhythm_take(id: StringName) -> void:
	await _approach(150.0)
	stage = String(id)
	pressed.clear()
	_log("take_start")
	master.start_clash_rhythm(id)
	driving = true
	var ticks := 0
	while master.clash_rhythm != null and ticks < 1000:
		await physics_frame
		ticks += 1
	driving = false
	_stop_move()
	# Let the production recovery/drink finish instead of resetting between moves.
	await _wait(0.6)
	while master.state == MasterBoss.State.DRINK: await physics_frame
	await _idle_player()
	_log("take_end")

func _punish_break() -> void:
	if not master.poise_broken or master.combat_stats.health <= 0 or master.state == MasterBoss.State.TRANSFORM: return
	stage = "poise_throw"
	await _approach(90.0)
	if lan.find_throw_target() == null: return
	_log("take_start")
	_press(&"interact")
	await _wait(0.1)
	if lan.attack_state == LanPlayer.AttackState.SPECIAL_ATTACK and lan.special_attack_max_form:
		throws += 1
		_log("throw")
	await _idle_player()
	_log("take_end")

func _counter() -> void:
	if master.combat_stats.health <= 0: return
	await _approach(145.0)
	stage = "charged_counter"
	_log("take_start")
	Input.action_press(&"special_attack")
	await _wait(0.48)
	Input.action_release(&"special_attack")
	await _idle_player()
	_log("take_end")

func _ultimate() -> void:
	if master.combat_stats.health <= 0: return
	await _approach(145.0)
	stage = "ultimate"
	_log("take_start")
	_key(KEY_O, true)
	await _wait(0.05)
	_key(KEY_O, false)
	await _wait(0.12)
	_key(KEY_O, true)
	await _wait(0.05)
	_key(KEY_O, false)
	if lan.ultimate_active:
		ultimates += 1
		_log("ultimate_started")
	await _idle_player()
	_log("take_end")

func _phase2(action: StringName) -> void:
	if master.combat_stats.health <= 0: return
	await _approach(165.0)
	stage = String(action)
	pressed.clear()
	p2_track = action
	_log("take_start")
	master._face_phase_2_target(lan.position.x-master.position.x)
	master._start_phase_2_attack(action)
	driving = true
	var ticks := 0
	while (master.state == MasterBoss.State.PHASE_2_ATTACK or master.red_parry_hold) and ticks < 900:
		await physics_frame
		ticks += 1
	driving = false
	p2_track = &""
	_stop_move()
	await _idle_player()
	_log("take_end")

func _physics_process(delta: float) -> bool:
	super._physics_process(delta)
	if not driving or p2_track == &"" or master.state != MasterBoss.State.PHASE_2_ATTACK: return false
	var hit_frames: Array = [8.0] if p2_track == &"phase_2_attack_1" else ([6.0] if p2_track == &"phase_2_dash" else [6.0, 11.0, 24.0])
	var now := float(master.animated_sprite.frame) + master.animated_sprite.frame_progress
	var fps := float(master.animated_sprite.sprite_frames.get_animation_speed(p2_track)) * master.body_base_speed * master.get_action_time_scale()
	for i in hit_frames.size():
		var left := (float(hit_frames[i])-now) / maxf(fps, 0.01)
		if left >= 0.0 and left <= 0.20 and not pressed.has(i):
			pressed[i] = true
			_press(&"parry")
	return false

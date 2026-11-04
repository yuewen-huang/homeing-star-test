extends SceneTree
var room
var deer: DeerBoss
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick(n: int) -> void:
	for i in n:
		deer._physics_process(1.0 / 60.0)
		room._physics_process(1.0 / 60.0)
		deer.vfx._process(1.0 / 60.0)
func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	DirAccess.make_dir_recursive_absolute(args[0])
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))
func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.select_combo(2)
	await wind_motion_contract()
	check(DeerClashPhase.LIBRARY.size() == 4, "Development library contains the current AI and three approved arrangements")
	var return_move: Dictionary = DeerAuthoredCombo.library().moves.deer_phase3_return_four
	check(return_move.events.back().danger == CombatAttackData.DangerType.COUNTERABLE_DANGER, "Return rhythm ends on its red counter instead of hiding a later uppercut")
	for i in range(1, return_move.events.size()):
		check(float(return_move.events[i].contact) - float(return_move.events[i - 1].contact) >= 0.35, "Rearranged contacts retain manual parry spacing")
	for retired in [&"three_ding", &"accel_five", &"delayed_feint", &"red_finale", &"three_cuts", &"heavy", &"thrust", &"rear_gore", &"flick", &"sweep"]:
		check(not deer.start_clash(retired, room.dummy.position.x), "Retired phase-three entry cannot start: " + String(retired))
	for i in 3:
		room.play_action(i)
		check(deer.clash_phase.action_id == DeerAuthoredCombo.IDS[i], "Shortcut starts the approved combo " + str(i + 1))
	room.play_action(3)
	check(deer.clash_phase.action_id == &"charge", "Gold pursuit remains callable without the retired crescent overlay")
	if not OS.get_cmdline_user_args().is_empty():
		tick(5)
		await capture("gold_warning")
		var captured := false
		for frame in 230:
			tick(1)
			await process_frame
			if not captured and deer.animated_sprite.animation == &"uppercut_ING":
				captured = true
				await capture("gold_active")
		await capture("gold_recovery")
	for i in DeerAuthoredCombo.IDS.size():
		room.select_combo_library(DeerClashPhase.LIBRARY.find(DeerAuthoredCombo.IDS[i]))
		room.play_action(4)
		check(is_instance_valid(deer.clash_phase.authored), "Development room starts " + DeerAuthoredCombo.label(DeerAuthoredCombo.IDS[i]))
		var combo := deer.clash_phase.authored
		check(combo.definition.events.size() == [3, 4, 5][i], "Imported event count matches approved arrangement")
		for step in 540:
			tick(1)
			if not OS.get_cmdline_user_args().is_empty(): await process_frame
			if step == 80: await capture("combo_%d" % i)
			if i == 2 and step == 265: await capture("heavy_front")
		check(room.dummy.contacts.size() == [3, 4, 5][i], "Real production probes reach all expected contacts: " + str(room.dummy.contacts.size()))
		print("CONTACTS ", JSON.stringify(room.dummy.contacts))
		check(deer.state == DeerBoss.State.IDLE and not is_instance_valid(deer.clash_phase.authored), "Recovery releases authored attack owner")
	room.play_action(4)
	tick(100)
	var combo := deer.clash_phase.authored
	var before := combo.time
	deer.action_clock.pause(0.2)
	tick(3)
	check(is_equal_approx(combo.time, before), "Shared hit stop freezes body and effects")
	deer.action_clock.clear()
	deer.enter_stagger(1)
	check(combo.cancelled and combo.attack_probes().is_empty(), "Stagger cancels all pending contacts immediately")
	tick(120)
	check(room.dummy.contacts.size() <= 3, "Cancelled attacks cannot arrive during recovery")
	deer.phase = 3
	deer.manual_control = false
	deer.phase_ai.choose(170)
	check(deer.clash_phase.action_id == &"dash" or deer.clash_phase.steps.any(func(s: Dictionary) -> bool: return s.move == &"authored"), "Production AI chooses retained dash or approved combos")
	deer.phase_ai.wind_repeat = 2
	deer.phase_ai.choose(170)
	check(deer.clash_phase.steps.any(func(s: Dictionary) -> bool: return s.move == &"authored"), "Long AI branch chooses approved authored combo")
	deer.manual_control = true
	deer._recover(0)
	check(DeerAuthoredCombo.HEAVY_RADIUS == 320 and DeerAuthoredCombo.ground_spec().width == 640, "Heavy quake visual and gameplay radius are expanded together")
	var spec := DeerAuthoredCombo.Ground.normalized(DeerAuthoredCombo.ground_spec())
	check(DeerAuthoredCombo.Ground.Profile.arrival(spec, 1.0) > DeerAuthoredCombo.Ground.Profile.arrival(spec, 0.5), "Heavy wave reaches the outer edge after the inner area")
	await contact_contract("normal")
	await contact_contract("parry")
	await contact_contract("red")
	await contact_contract("dodge")
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"deer_phase3_mountain_six"))
	room.play_action(4)
	var heavy := deer.clash_phase.authored
	var event: Dictionary = heavy.definition.events.back()
	heavy.advance(float(event.release) + 0.32, 0.32)
	var center: Vector2 = heavy.rows.back().effect.global_position
	var point := CircleShape2D.new()
	point.radius = 1
	for distance in [270.0, 310.0, 350.0]:
		var reached := false
		for probe: Dictionary in heavy.attack_probes():
			if probe.shape.collide(probe.transform, point, Transform2D(0, center + Vector2(distance, -24))): reached = true
		check(reached == (distance < 320), "Ground front range at " + str(distance))
	deer._recover(0)
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"deer_phase3_forest_five"))
	room.set_playback_speed(0)
	room.play_action(4)
	tick(1150)
	check(room.dummy.contacts.size() == 3 and deer.state == DeerBoss.State.IDLE, "Quarter speed preserves all contacts and clean completion")
	room.set_playback_speed(2)
	room.play_action(4)
	var dying := deer.clash_phase.authored
	deer.combat_target.combat_stats.health_depleted.emit()
	check(dying.cancelled and dying.attack_probes().is_empty(), "Player defeat clears effects and pending contacts immediately")
	room.play_action(4)
	var switched := deer.clash_phase.authored
	room.select_combo(0)
	check(switched.cancelled and deer.phase == 1, "Phase switch clears imported combat effects")
	# The mist core's simple horn attack used to read the retired move table.
	var phantom := RegionalMistSummon.new()
	phantom.kind = RegionalMistSummon.Kind.PHANTOM
	phantom.core = deer
	phantom.preview_only = true
	room.add_child(phantom)
	var horn := RegionalPhantomSpell.new()
	horn.core = deer
	horn.phantom = phantom
	horn.preview_only = true
	room.add_child(horn)
	for facing in [-1.0, 1.0]:
		phantom.facing = facing
		horn.step(0.01)
		check(horn.contact_shapes.size() == 1 and horn.contact_shapes[0].shape.size.is_equal_approx(Vector2(89.6, 103.04)), "Regional phantom retains the original horn footprint, facing " + str(facing))
	check(horn.attack.danger_type == CombatAttackData.DangerType.NORMAL, "Regional phantom retains ordinary parry semantics")
	horn.step(0.3)
	check(horn.finished and horn.contact_shapes.is_empty(), "Regional phantom closes its original three-frame active window")
	current_scene = null
	room.free()
	await process_frame
	print("DEER AUTHORED: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func wind_motion_contract() -> void:
	room.play_action(0)
	var combo := deer.clash_phase.authored
	var event: Dictionary = combo.definition.events[1]
	combo.advance(lerpf(float(event.release), float(event.end), .4), 0)
	var row: Dictionary = combo.rows[1]
	var effect = row.effect
	check(effect.motion_kind == "sweep", "Head flick uses a swept sheet instead of a translated punch front")
	check(not is_equal_approx(effect._width_at(0.0), effect._width_at(1.0)), "Flick retains the source's varying blade breadth")
	check(effect.speed_at(.15) > effect.speed_at(.75) * 3.0, "Wind deformation follows the fast release and slow settle")
	var vertices: PackedVector2Array = effect._body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tip := (vertices[-1] + vertices[-2]) * .5
	var tip_world: Vector2 = row.anchor.global_transform * tip
	check(tip_world.distance_to(row.probes[0].transform.origin) < .01, "Rendered sheet tip and real contact share one path clock")
	var start := (vertices[0] + vertices[1]) * .5
	var middle := (vertices[64] + vertices[65]) * .5
	var chord := tip - start
	check(absf(chord.cross(middle - start)) / maxf(1.0, chord.length()) > 15.0, "Sweep silhouette actually bends through the arc")
	check(effect._lens == null or effect._lens.visible, "Native swept wind retains its transparent pressure ring")
	if effect._lens != null:
		var ring_center: Vector2 = effect._lens.transform * Vector2(.58, .5)
		check(ring_center.distance_to(tip) < .01, "Pressure ring follows the moving contact rather than the source origin")
		check(effect._copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "Mirrored pressure ring copies a complete screen source")
	effect.advance(0.0)
	check(vertices == effect._body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "A paused action cannot advance or deform the wind")
	await capture("wind_sweep_active")
	deer._recover(0)

func contact_contract(mode: String) -> void:
	var original: LanPlayer = deer.combat_target
	var target: LanPlayer = load("res://scenes/player/lan/lan_player.tscn").instantiate()
	target.world_min_x = -2000
	target.world_max_x = 4000
	room.add_child(target)
	await process_frame
	target.set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"deer_phase3_forest_five"))
	room.play_action(4)
	deer.combat_stats.restore_poise()
	var combo := deer.clash_phase.authored
	var event: Dictionary = combo.definition.events.back() if mode == "red" else combo.definition.events[0]
	combo.advance(lerpf(float(event.release), float(event.end), 0.5), 0.4)
	var row: Dictionary = combo.rows.back() if mode == "red" else combo.rows[0]
	var probe: Dictionary = row.probes[0]
	target.global_position = (probe.transform as Transform2D).origin + Vector2(0, 29)
	target.facing_direction = -deer.direction
	if mode in ["parry", "red"]: target.start_parry()
	if mode == "dodge": target.start_back_dodge()
	var health := target.combat_stats.health
	deer.combat_target = target
	deer.manual_control = false
	combo._resolve(row)
	if mode == "normal":
		check(target.combat_stats.health == health - CombatTuning.boss_player_damage(CombatAttackData.DangerType.NORMAL), "Live authored strike deals shared tuned damage")
		combo._resolve(row)
		check(target.combat_stats.health == health - CombatTuning.boss_player_damage(CombatAttackData.DangerType.NORMAL), "One active strike cannot repeat damage")
	elif mode == "parry":
		check(target.combat_stats.health == health and deer.clash_phase.parry_streak > 0 and not combo.cancelled, "Ordinary parry freezes and resumes approved combo")
	elif mode == "red":
		check(target.combat_stats.health == health and combo.cancelled and deer.red_parry_hold, "Red parry cancels approved combo through shared response")
	else:
		check(target.combat_stats.health == health and row.hitbox.hit_targets.has(target.get_instance_id()), "Dodge evades and settles the strike only once")
	deer.combat_target = original
	deer.manual_control = true
	deer.red_parry_hold = false
	deer.action_clock.clear()
	deer._recover(0)
	target.free()
	# Shared feedback owns real-time hit stop; let it release before the next sample.
	while Engine.time_scale < 1: await process_frame

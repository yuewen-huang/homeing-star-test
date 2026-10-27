extends "../../support/harness.gd"
var master: MasterBoss
var lan: LanPlayer
var results: Array[int] = []

func fresh(direction := 1.0) -> MasterPhase1Action:
	master._cancel_phase_1_action()
	master.phase = 1
	master.manual_control = true
	master.position = Vector2(0, 555)
	master.movement_direction = direction
	master.combat_stats.restore_health()
	master.combat_stats.restore_poise()
	master.poise_broken = false
	master.parry_pause_remaining = 0
	master.red_parry_hold = false
	master.action_clock.clear()
	lan.reset_after_map_fall(Vector2(2000,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	results.clear()
	master.start_phase_1_action(&"mountain")
	return master.phase_1_action

func emit(action: MasterPhase1Action) -> MasterMountainSwordQi:
	action.advance(float(action.timeline.cuts[1].contact_at) + 0.001)
	return action.mountain_wave

func meet(wave: MasterMountainSwordQi, time := 0.2) -> void:
	var point := (wave._edge(time,0,false) + wave._edge(time,0,true)) * 0.5
	lan.global_position = wave.to_global(point) + Vector2(0,29)

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	master.attack_hitbox.hit_resolved.connect(func(_target: Node, result: CombatHitResult.Type) -> void: results.append(int(result)))
	await physics_frame
	for direction in [-1.0,1.0]:
		var action := fresh(direction)
		var contact := float(action.timeline.cuts[1].contact_at)
		action.advance(contact - 0.001)
		check(action.mountain_wave == null,"No sword qi during uppercut, windup or before the downward impact")
		action.advance(0.002)
		var wave := action.mountain_wave
		wave.set_process(false)
		var saved: Dictionary=wave.studio_profile("mountain")
		var expected: Dictionary=wave.Ground.normalized(saved.event)
		var sink := float(saved.event.get("sink",.2 if saved.event.get("trail")=="flame" else 0.0))
		check(wave != null and wave.effect.spec.form=="crescent" and wave.effect.spec.trail==saved.event.trail and is_equal_approx(wave.effect.spec.sink,sink),"Production selects the saved editor form, trail and burial")
		check(wave.effect.spec.ramp==MasterPhase1Palette.ramp_stops() and wave.effect.style==String(saved.style.get("quake_style","real")),"Game keeps its owner palette and the saved renderer style")
		var visible_height := wave.Shapes.crescent_height(wave._height(0),float(wave.effect.spec.sink))
		var saved_height := wave.Shapes.crescent_height(clampf(float(expected.width)*.8,70,230)*float(expected.unit_size)*1.3,sink)
		check(is_equal_approx(visible_height,saved_height),"Production retains the editor's saved wave size")
		var all_fields := true
		for key in ["width","length","unit_size","body_growth","travel","ease","angle","debris_density","debris_height","crack_amount"]:
			all_fields=all_fields and is_equal_approx(float(wave.effect.spec[key]),float(expected[key]))
		check(all_fields,"Saved size, growth, speed, angle and ground settings all reach production")
		check(is_equal_approx(float(wave.effect.spec.width)+float(wave.effect.spec.length),float(expected.width)+float(expected.length)),"Wave travel distance follows the saved editor profile")
		check(is_equal_approx(wave._edge(0,1,false).y,-visible_height),"Current collision blade uses the same full-height crescent as the renderer")
		check(is_equal_approx(wave._height(1)/wave._height(0),float(expected.body_growth)),"The blade follows saved visual growth during flight")
		check(wave.attack == action._attack and wave.attack.danger_type == CombatAttackData.DangerType.NORMAL,"Falling sword and qi share the same normal parryable attack")
		var foot: Vector2=wave.effect.position+wave.effect.ground(Vector2(-wave.effect.extent(),0))+wave.Shapes.crescent_foot(wave.effect.outward(Vector2.ZERO),wave._height(0),sink)
		check(foot.length() < 0.001 and is_equal_approx(wave.global_position.y,555),"Measured impact anchors the buried crescent foot on the floor")
		check(signf(wave.to_global(wave._edge(0.5,0,false)).x - wave.to_global(wave._edge(0.1,0,false)).x) == direction,"Sword qi travels forward in both facings")
		meet(wave)
		wave.advance(0.2 - wave.effect.age)
		check(results.is_empty() and lan.combat_stats.health == 100,"Development visual preview never deals sword-qi damage")
		master.manual_control = false
		lan.start_parry(true)
		wave._resolve(0.19,0.2)
		check(results == [int(CombatHitResult.Type.PARRY_SUCCESS)] and lan.combat_stats.health == 100,"Live crescent supports the shared normal parry")
		check(master.combat_stats.poise == master.combat_stats.max_poise - CombatTuning.BOSS_NORMAL_PARRY_POISE,"Parry returns the shared boss poise settlement")
		wave._resolve(0.19,0.2)
		check(results.size() == 1,"One falling strike settles once despite lingering flames")
		master.parry_pause_remaining = 0
		var wave_id := wave.get_instance_id()
		action.advance(0.1)
		check(action.mountain_wave.get_instance_id() == wave_id,"The downward strike emits exactly one crescent")
	for difficulty in [0,1,2]:
		assist.set_difficulty(difficulty as BattleAssistSettingsService.Difficulty)
		var wave := emit(fresh())
		master.manual_control = false
		meet(wave)
		var damage := CombatTuning.boss_player_damage(CombatAttackData.DangerType.NORMAL)
		wave._resolve(0.19,0.2)
		check(lan.combat_stats.health == 100 - damage,"Qi uses current difficulty damage: %d" % difficulty)
		check(master.attack_hitbox.hit_targets.has(lan.get_instance_id()),"Qi immediately shares its hit ledger with the still-active falling blade")
	var action := fresh()
	action.advance(float(action.timeline.cuts[1].contact_at) - 0.001)
	master.attack_hitbox.hit_targets[lan.get_instance_id()] = true
	action.advance(0.002)
	var wave := action.mountain_wave
	master.manual_control = false
	meet(wave)
	wave._resolve(0.19,0.2)
	check(results.is_empty(),"A target already struck by the falling blade cannot be hit again by qi")
	wave = emit(fresh())
	master.manual_control = false
	meet(wave)
	lan.global_position.y -= 220
	wave._resolve(0.19,0.2)
	check(results.is_empty(),"Jumping above the visible crescent avoids its blade")
	meet(wave)
	lan.start_back_dodge(-1)
	lan.combat_timeline.seek(0.01 * lan.BACK_DODGE_SPEED_SCALE, true)
	wave._resolve(0.19,0.2)
	check(results == [int(CombatHitResult.Type.EVADED)] and lan.combat_stats.health == 100,"Qi respects the shared dodge invulnerability")
	wave = emit(fresh())
	master.manual_control = false
	meet(wave)
	lan.global_position.x += 39
	lan.start_parry(true)
	wave._resolve(0.19,0.2)
	check(results == [int(CombatHitResult.Type.PARRY_SUCCESS)],"A close visual graze can use the shared extended parry catch")
	wave = emit(fresh())
	master.manual_control = false
	meet(wave)
	wave._resolve(0.6,0.7)
	check(results.is_empty(),"The scar, flames and afterimages cannot deal late damage")
	action = fresh()
	wave = emit(action)
	action.advance(action.timeline.duration - action.elapsed + 0.01)
	check(master.phase_1_action == null and wave.get_parent() == master and wave.tail_only,"Normal recovery preserves the complete visual tail after the body finishes")
	wave.set_process(false)
	master._enter_phase_2()
	check(not wave.active and not wave.visible,"Phase handoff immediately clears the surviving visual tail")
	action = fresh()
	wave = emit(action)
	master._interrupt_for_special(0)
	check(not wave.active and master.phase_1_action == null,"Interruption cancels body, crescent and all lingering effects")
	action = fresh()
	wave = emit(action)
	var old_age: float = wave.effect.age
	master.parry_pause_remaining = 0.1
	master._process(0.01)
	check(is_equal_approx(wave.effect.age,old_age),"Parry hit-stop freezes sword qi together with the body")
	master.parry_pause_remaining = 0
	master.action_clock.extend_dodge_slow(1.0)
	master._process(0.1)
	check(is_equal_approx(wave.effect.age-old_age,0.025),"Sword qi and body share the 0.25x dodge clock")
	master.action_clock.clear()
	for id: StringName in MasterActionLibrary.MOVE_IDS:
		if id == &"mountain": continue
		fresh()
		master.start_phase_1_action(id)
		action = master.phase_1_action
		action.advance(action.timeline.duration - 0.01)
		check(action.mountain_wave == null,"Only standalone mountain gains qi: " + id)
	if DisplayServer.get_name() != "headless":
		action = fresh()
		wave = emit(action)
		wave.global_position = Vector2(400,555)
		for time in [0.05,0.2,0.4,0.7]:
			wave.advance(time-wave.effect.age)
			await process_frame
			await process_frame
		check(true,"Real renderer draws the saved ground wave and complete ground effects")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER MOUNTAIN SWORD QI")

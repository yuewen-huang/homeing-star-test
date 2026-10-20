extends "../../support/harness.gd"
## Production-room regression for the 2026-10-20 stable long strings.
var room: Node2D
var master: MasterBoss
var player: LanPlayer
var outcomes: Array[int] = []
var source_actions: Array[StringName] = []

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func tick_to(time: float) -> void:
	var guard := 0
	while master.clash_rhythm != null and master.clash_rhythm.elapsed + 0.000001 < time and guard < 4000:
		master._process(minf(1.0 / 120.0, time - master.clash_rhythm.elapsed))
		guard += 1

func place() -> void:
	master._interrupt_for_special(0.0)
	master.poise_broken = false
	master.combat_stats.restore_poise()
	master.position = Vector2(260, 555)
	player.reset_after_map_fall(Vector2(110, 555))
	player.combat_stats.restore_health()
	player.set_physics_process(false)

func settle_guard() -> void:
	player.defense_state = LanPlayer.DefenseState.NONE
	player.defense_recoil_active = false
	player.hit_reaction_active = false
	player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
	player.play_idle()
	player.start_parry()
	player.animated_sprite.frame = 3
	player.on_player_animation_frame_changed()
	player.animated_sprite.pause()
	outcomes.clear()
	await physics_frame
	await physics_frame
	master.attack_hitbox._physics_process(0)

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.get_node("MasterBoss")
	player = room.get_node("Lan")
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	player.set_physics_process(false)
	master.attack_hitbox.hit_resolved.connect(func(target: Node, result: int) -> void:
		if target == player: outcomes.append(result))
	var expected := {&"basic_down": 1, &"return_chain": 3, &"press_return": 6, &"blink_return": 6, &"spin_delayed": 5, &"air_plunge": 3}
	for id: StringName in MasterClashRhythm.ORDER:
		place()
		master.start_clash_rhythm(id)
		var r := master.clash_rhythm
		check(r.strikes.size() == expected[id], "%s has the intended melee contacts" % id)
		var dangers := {}
		for strike: Dictionary in r.strikes: dangers[strike.danger] = int(dangers.get(strike.danger, 0)) + 1
		if id == &"spin_delayed":
			check(dangers == {&"normal": 4, &"red": 1}, "Only the last heavy cut is red")
		elif id == &"air_plunge":
			check(dangers == {&"normal": 2, &"gold": 1}, "Only the landing is gold")
		else:
			check(not dangers.has(&"red") and not dangers.has(&"gold"), "%s stays parryable white" % id)
		for entry: Array in r.track:
			if entry[0] not in source_actions: source_actions.append(entry[0])
		if id in [&"press_return", &"blink_return", &"spin_delayed"]:
			for i in range(1, r.strikes.size()):
				var gap: float = r.strikes[i].t - r.strikes[i-1].t
				check(gap >= 0.59 and gap <= 0.91, "%s contact spacing stays readable: %.2f" % [id, gap])
		var health := player.combat_stats.health
		var budget := 0
		for i in r.strikes.size():
			tick_to(float(r.strikes[i].t) - 0.15)
			for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()
			if i == 0: await capture(String(id) + "_warning")
			tick_to(float(r.strikes[i].t) + 0.025)
			await capture(String(id) + "_cut_%d" % i)
			check(master.attack_hitbox.attack != null, "%s beat %d opens its real hitbox" % [id, i])
			budget += master.attack_hitbox.attack.health_damage
			if r.data.get("sequence", false):
				check(not master.wind_effect.visible and r.winds.back().node is MasterTrajectoryRibbon, "%s uses retained trajectory only" % id)
				var trail: MasterTrajectoryRibbon = r.winds.back().node
				check(not trail.samples.is_empty() and trail.blade.mesh != null, "Trajectory has actual retained blade samples and triangles")
			# The aerial landing moves the master; grounded contacts still test real parries.
			if r.strikes[i].danger == &"gold":
				# The one gold beat is unparryable by design; its hitbox is checked above.
				continue
			await settle_guard()
			check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS), "%s beat %d settles a real manual Lan parry" % [id, i])
			check(player.combat_stats.health == health, "Successful parries preserve health")
			if master.parry_pause_remaining > 0:
				var age := r.elapsed
				master._process(0.02)
				check(is_equal_approx(age, r.elapsed), "Parry hit-stop freezes the production action clock")
		if id in [&"press_return", &"blink_return"]: check(budget == 30, "Six-cut damage budget is 30, not 60")
		if id == &"spin_delayed": check(budget == 32, "Five escalating cuts have a bounded 32 damage budget")
		tick_to(r.duration - 0.01)
		await capture(String(id) + "_recovery")
		tick_to(r.duration + 0.01)
		check(master.clash_rhythm == null and master.attack_hitbox.attack == null, "Full recovery closes combat state")
		var total_opening: float = master.recovery_remaining + r.duration - float(r.strikes[-1].close)
		check(total_opening >= (1.59 if id in [&"blink_return", &"spin_delayed", &"air_plunge"] else 1.19), "Guaranteed punish window includes authored recovery")
	check(source_actions.has(&"attack_1") and source_actions.has(&"attack_2") and source_actions.has(&"attack_3") and source_actions.has(&"dash") and source_actions.has(&"special_attack") and source_actions.has(&"air_spin_slam") and source_actions.has(&"heavy_cut"), "Every main authored attack has a production use")
	check(MasterClashRhythm.unlocked_for_layer(0) == [&"basic_down", &"return_chain"], "Opening starts with familiar short teaching moves")
	check(MasterClashRhythm.unlocked_for_layer(1).has(&"press_return") \
		and MasterClashRhythm.unlocked_for_layer(4).size() == 6, "Each drink teaches the next string")
	master.manual_control = false
	master.opening_lessons_started = 0
	for id: StringName in MasterBoss.OPENING_LESSONS:
		check(master.choose_clash_rhythm() == id, "Opening order is deterministic")
		master.start_clash_rhythm(id)
	# Regression (2026-10-20): the opening ends with return_chain twice while only
	# [basic_down, return_chain] are unlocked. The plain cut was erased first, the repeat
	# broke next, and the empty pool reached `randi() % 0` ("Modulo by zero", master_boss.gd:596).
	check(master.opening_lessons_started == MasterBoss.OPENING_LESSONS.size(), "Opening lessons are exhausted")
	check(master.charged_power == 0, "Opening lessons spend no spirit layer")
	master.combat_stats.restore_health()
	master.introduced_rhythms = [&"basic_down", &"return_chain"]
	master.recent_rhythms = [&"return_chain", &"return_chain"]
	check(master.choose_clash_rhythm() == &"basic_down", "A repeated string steps aside instead of emptying the pool")
	master.recent_rhythms = [&"return_chain", &"basic_down"]
	check(master.choose_clash_rhythm() == &"return_chain", "A mixed history keeps the taught string in rotation")
	master.recent_rhythms = [&"basic_down", &"basic_down"]
	check(master.choose_clash_rhythm() == &"return_chain", "The plain cut never repeats three times either")
	# A wide pool still prunes the triple repeat and the plain filler, never the last option.
	master.charged_power = 4
	master.introduced_rhythms.assign(MasterClashRhythm.unlocked_for_layer(4))
	master.recent_rhythms = [&"press_return", &"press_return"]
	var taught: StringName = master.choose_clash_rhythm()
	check(taught != &"press_return" and taught != &"basic_down", "A wide pool avoids the third repeat and the filler")
	check(MasterClashRhythm.RHYTHMS.has(taught), "The chosen rhythm is always playable")
	master.charged_power = 0
	master.combat_stats.restore_health()
	master.introduced_rhythms = [&"basic_down", &"return_chain"]
	master.recent_rhythms = [&"return_chain", &"return_chain"]
	master.manual_control = true
	place()
	master.start_clash_rhythm(&"air_plunge")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	player.parry_chain.begin(master, 0.0)
	check(player.parry_chain.covers(master, 1.6), "Normal assist spans the grounded-to-airborne transition")
	master.start_clash_rhythm(&"press_return")
	check(not player.parry_chain.covers(master, 1.7), "A new string always requires a new first parry")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(not assist.uses_parry_chain_assist(), "Hard keeps every contact manual")
	place()
	master.start_clash_rhythm(&"spin_delayed")
	tick_to(1.02)
	var ribbon: MasterTrajectoryRibbon = master.clash_rhythm.winds.back().node
	var elapsed := ribbon.age
	var origin := ribbon.global_position
	master.start_parry_feedback()
	master._process(0.02)
	check(is_equal_approx(ribbon.age, elapsed), "Retained geometry does not advance during parry pause")
	master.position.x += 80
	check(ribbon.global_position == origin, "Retained world trajectory is not dragged by a later movement")
	master._interrupt_for_special(0.0)
	for i in 100: master._process(1.0 / 60.0)
	await process_frame
	check(master.fading_winds.is_empty(), "Interrupted ribbons finish and clean up on the action clock")
	# Full phase-one walk (2026-10-20): only the long strings pour a drink, and each drink
	# introduces the next string, so the sixth drink only arrives after all six have played.
	master.charged_power = 0
	master.opening_lessons_started = MasterBoss.OPENING_LESSONS.size()
	master.introduced_rhythms.assign([&"basic_down", &"return_chain"])
	master.recent_rhythms.assign([&"return_chain", &"return_chain"])
	var seen: Array[StringName] = [&"basic_down", &"return_chain"]
	var steps := 0
	while master.phase == 1 and steps < 80:
		steps += 1
		var pick: StringName = master.choose_clash_rhythm()
		if pick not in seen: seen.append(pick)
		master.start_clash_rhythm(pick)
		master.clash_rhythm.advance(master.clash_rhythm.duration + 0.01)
		var pours: bool = pick in [&"return_chain", &"spin_delayed", &"air_plunge"]
		check(master.pending_drink == pours, "%s follows the long-string drink rule" % pick)
		master._update_recovery(master.recovery_remaining + 0.01)
		if pours: master._finish_drink()
	check(steps < 80, "Phase one reaches six layers inside the walk budget")
	check(master.phase == 2 and master.state == MasterBoss.State.TRANSFORM, "The sixth drink transforms him")
	check(seen.size() == MasterClashRhythm.ORDER.size(), "All six rhythms played in one phase one (seen %s)" % [seen])
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER STABLE RHYTHMS")

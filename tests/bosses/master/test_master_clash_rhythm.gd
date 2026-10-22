extends "../../support/harness.gd"
## Production-room regression for the 2026-10-21 five-move table: one cut, the return
## chain, and the three motion samples.
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
		var r := master.clash_rhythm
		var remaining := r.played_time_at(time)-r.played_time_at(r.elapsed)
		master._process(minf(1.0 / 120.0, remaining))
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
	# Test the actual moving blade, which no longer fills the old broad rectangle.
	var collision := master.attack_collision_shape
	var center := Vector2.ZERO
	for point in (collision.shape as ConvexPolygonShape2D).points: center += point
	center /= float((collision.shape as ConvexPolygonShape2D).points.size())
	player.position = collision.to_global(center) + Vector2(0, 43)
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

	check(MasterClashRhythm.ORDER.size() == 4 and &"smear_sample" not in MasterClashRhythm.ORDER,
		"The formal move table holds four entries independently of archived samples")
	var expected := {&"basic_down": 1, &"inertia_combo": 5, &"lunge_combo": 6, &"air_qi_combo": 8}
	for id: StringName in MasterClashRhythm.ORDER:
		place()
		master.start_clash_rhythm(id)
		var r := master.clash_rhythm
		check(r != null and r.id == id, "%s starts its production rhythm" % id)
		check(r.strikes.size() == expected[id], "%s has the intended melee contacts" % id)
		for strike: Dictionary in r.strikes:
			check(strike.danger == &"normal", "%s stays parryable white" % id)
		for entry: Array in r.track:
			if entry[0] not in source_actions: source_actions.append(entry[0])
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
				var trail: MasterTrajectoryRibbon = null
				for wind: Dictionary in r.winds:
					if wind.node is MasterTrajectoryRibbon: trail = wind.node
				check(trail != null and not trail.samples.is_empty(),
					"%s grows its live retained blade trajectory" % id)
			# Place Lan on each current blade and settle through her real defense route.
			await settle_guard()
			check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS), "%s beat %d settles a real manual Lan parry" % [id, i])
			check(player.combat_stats.health == health, "Successful parries preserve health")
			if master.parry_pause_remaining > 0:
				var age := r.elapsed
				master._process(0.02)
				check(is_equal_approx(age, r.elapsed), "Parry hit-stop freezes the production action clock")
		if id in [&"inertia_combo", &"lunge_combo", &"air_qi_combo"]:
			check(budget == 5 * expected[id], "%s keeps a local 5-per-cut damage budget" % id)
		tick_to(r.duration - 0.01)
		await capture(String(id) + "_recovery")
		tick_to(r.duration + 0.01)
		check(master.clash_rhythm == null and master.attack_hitbox.attack == null, "Full recovery closes combat state")

	check(source_actions.has(&"attack_1") and source_actions.has(&"attack_2") and source_actions.has(&"attack_3") \
		and source_actions.has(&"dash") and source_actions.has(&"air_spin_slam"), "The reviewed mixed-action combos are in the formal table")
	check(MasterClashRhythm.unlocked_for_layer(0) == [&"basic_down", &"inertia_combo"], "Opening starts with the familiar pair")
	check(MasterClashRhythm.unlocked_for_layer(1).has(&"inertia_combo") \
		and MasterClashRhythm.unlocked_for_layer(3).size() == 4, "Each drink teaches the next sample")
	master.manual_control = false
	master.opening_lessons_started = 0
	for id: StringName in MasterBoss.OPENING_LESSONS:
		check(master.choose_clash_rhythm() == id, "Opening order is deterministic")
		master.start_clash_rhythm(id)
	check(master.opening_lessons_started == MasterBoss.OPENING_LESSONS.size(), "Opening lessons are exhausted")
	check(master.charged_power == 0, "Opening lessons spend no spirit layer")
	master.combat_stats.restore_health()
	master.introduced_rhythms = [&"basic_down", &"inertia_combo"]
	master.recent_rhythms = [&"inertia_combo", &"inertia_combo"]
	check(master.choose_clash_rhythm() == &"basic_down", "A repeated string steps aside instead of emptying the pool")
	master.recent_rhythms = [&"inertia_combo", &"basic_down"]
	check(master.choose_clash_rhythm() == &"inertia_combo", "A mixed history keeps the taught string in rotation")
	master.recent_rhythms = [&"basic_down", &"basic_down"]
	check(master.choose_clash_rhythm() == &"inertia_combo", "The plain cut never repeats three times either")
	# A wide pool still prunes the triple repeat and the plain filler.
	master.charged_power = 4
	master.introduced_rhythms.assign(MasterClashRhythm.unlocked_for_layer(4))
	master.recent_rhythms = [&"inertia_combo", &"inertia_combo"]
	var taught: StringName = master.choose_clash_rhythm()
	check(taught != &"inertia_combo" and taught != &"basic_down", "A wide pool avoids the third repeat and the filler")
	check(MasterClashRhythm.RHYTHMS.has(taught), "The chosen rhythm is always playable")

	# Retained geometry ignores parry pauses and later movement.
	master.manual_control = true
	place()
	master.start_clash_rhythm(&"inertia_combo")
	tick_to(0.55)
	var ribbon: MasterTrajectoryRibbon = null
	for wind: Dictionary in master.clash_rhythm.winds:
		if wind.node is MasterTrajectoryRibbon: ribbon = wind.node
	check(ribbon != null, "The first sample cut keeps its ribbon")
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

	# Normal assist spans the sample's own jump; a new string requires a new first parry.
	place()
	master.start_clash_rhythm(&"air_qi_combo")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	player.parry_chain.begin(master, 0.0)
	check(player.parry_chain.covers(master, 1.6), "Normal assist spans the airborne sample")
	master.start_clash_rhythm(&"inertia_combo")
	check(not player.parry_chain.covers(master, 1.7), "A new string always requires a new first parry")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(not assist.uses_parry_chain_assist(), "Hard keeps every contact manual")

	# Full phase-one walk: only the long strings pour a drink, and each drink introduces
	# the next sample, so six drinks only arrive after the table has played.
	master.charged_power = 0
	master.opening_lessons_started = MasterBoss.OPENING_LESSONS.size()
	master.introduced_rhythms.assign([&"basic_down", &"inertia_combo"])
	master.recent_rhythms.assign([&"inertia_combo", &"inertia_combo"])
	var pours_ids := [&"inertia_combo", &"lunge_combo", &"air_qi_combo"]
	var seen: Array[StringName] = [&"basic_down", &"inertia_combo"]
	var steps := 0
	while master.phase == 1 and steps < 80:
		steps += 1
		var pick: StringName = master.choose_clash_rhythm()
		if pick not in seen: seen.append(pick)
		master.start_clash_rhythm(pick)
		master.clash_rhythm.advance(master.clash_rhythm.played_time_at(master.clash_rhythm.duration) + 0.01)
		var pours: bool = pick in pours_ids
		check(master.pending_drink == pours, "%s follows the long-string drink rule" % pick)
		master._update_recovery(master.recovery_remaining + 0.01)
		if pours: master._finish_drink()
	check(steps < 80, "Phase one reaches six layers inside the walk budget")
	check(master.phase == 2 and master.state == MasterBoss.State.TRANSFORM, "The sixth drink transforms him")
	check(seen.size() == MasterClashRhythm.ORDER.size(), "All four moves played in one phase one (seen %s)" % [seen])
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER STABLE RHYTHMS")

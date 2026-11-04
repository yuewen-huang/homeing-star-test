extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var contacts: Array[int] = []

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	deer = room.adapter.boss
	lan = room.player
	room.set_physics_process(false)
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	check(deer.manual_control and not room.combat_simulation, "Phase one defaults to protected manual preview")
	check(room.combat_toggle.is_visible_in_tree(), "Complete phase exposes opt-in combat")
	for index in 4:
		room.adapter.play_action(index)
		deer.set_physics_process(false)
		var health := lan.combat_stats.health
		var saw := false
		for frame in 300:
			tick()
			saw = saw or not deer.attack_probes().is_empty()
		check(saw, "Move %d exposes actual contact probes" % index)
		check(lan.combat_stats.health == health, "Move %d leaves observer safe" % index)
	room.set_combat_simulation(true)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	for index in 4:
		reset_pair()
		if index == 2: deer.position.x = 605
		deer.start_move(index,lan.position.x)
		var health := lan.combat_stats.health
		for frame in 300: tick()
		check(lan.combat_stats.health < health, "Undefended move %d really hits standing Lan" % index)
		check(contacts.size() == 1, "Move %d settles at most once, including leaf return" % index)
	# Locked trajectories cannot reacquire a target after the cue.
	for index in [0,1,2]:
		reset_pair()
		deer.start_move(index,lan.position.x)
		var aim := deer._aim
		var facing := deer.direction
		for frame in 25: tick()
		lan.position.x = 1000
		for frame in 90: tick()
		check(deer._aim == aim and deer.direction == facing, "Move %d retains cue direction and landing target" % index)
	reset_pair()
	deer.start_move(1,lan.position.x)
	for frame in 48: tick()
	var airborne_hurt := deer.get_node("Hurtbox").get_child(0) as CollisionShape2D
	check(airborne_hurt.position.distance_to(deer.body_center_offset()) < 1,"Leaping hurtbox follows the visible torso, not the empty floor")
	check(airborne_hurt.global_position.y+75 < 500,"Leaping hurtbox leaves the ground attack lane")
	reset_pair()
	deer.start_move(3,lan.position.x)
	for frame in 55: tick()
	var before := deer.age
	var at := deer.effects.leaf_center
	deer.red_parry_hold = true
	for frame in 30: tick()
	check(deer.age == before and deer.effects.leaf_center == at, "Shared action hold freezes leaf and body together")
	var effect_clock := deer.effects.clock
	var swarm_clock: float = deer.effects._swarm.clock
	for frame in 20: tick()
	check(deer.effects.clock == effect_clock and deer.effects._swarm.clock == swarm_clock,"Studio shader and swarm clocks freeze during action hold")
	deer.red_parry_hold = false
	deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
	check(deer.poise_broken and deer.opening >= 1.4 and deer.attack_probes().is_empty(), "Real poise break cancels hazards and opens punish")
	check(deer.effects._main.is_empty() and deer.effects._leaf_alpha == 0,"Poise break removes the visible attack core immediately")
	var tail_start := deer.effects.clock
	for frame in 120:
		if deer.effects._tail_age < 0: break
		tick()
	check(deer.effects._parts.size() == 2 and deer.effects._ambient and deer.effects.clock-tail_start <= .5 and deer.opening > 0,"Attack tail returns to the two ambient leaf layers within half an action second and inside punish")
	# Cosmetic transforms and complete visual teardown cannot resize/cancel damage.
	for index in [0,1,2,3]:
		reset_pair()
		deer.manual_control = true
		deer.start_move(index,lan.position.x)
		var steps := [45,65,39,55]
		for frame in steps[index]: tick()
		var probes := deer.attack_probes()
		check(not probes.is_empty(),"Move %d has an active authoritative shape for VFX isolation" % index)
		var original_transform: Transform2D = probes[0].transform
		var original_rect: Rect2 = probes[0].shape.get_rect()
		deer.effects.scale = Vector2(3,2)
		deer.effects.clear()
		var after := deer.attack_probes()
		check(after.size() == probes.size() and after[0].transform == original_transform and after[0].shape.get_rect() == original_rect,"Move %d damage is independent of Studio scale and lifetime" % index)
		deer.effects.scale = Vector2.ONE
	reset_pair()
	deer.start_move(3,lan.position.x)
	for frame in 60: tick()
	deer.combat_stats.apply_health_damage(deer.combat_stats.health)
	check(deer._stopped and deer.attack_probes().is_empty() and deer.effects.kind == &"", "Defeat clears the returning leaf")
	# Contextual selector, capped repetition, no one-move stage or compulsory loop.
	reset_pair()
	deer._rng.seed = 20261104
	var seen := {}
	var orders := {}
	var previous := -1
	var repeats := 0
	var max_repeats := 0
	for i in 80:
		var selected := deer.choose_move(260)
		seen[selected] = true
		orders["%d_%d" % [previous,selected]] = true
		repeats = repeats+1 if selected == previous else 1
		max_repeats = maxi(repeats,max_repeats)
		previous = selected
		deer.start_move(selected,lan.position.x)
	check(seen.size() == 4 and orders.size() > 8 and max_repeats <= 2, "Contextual repertoire covers four moves without round robin or repeated spam")
	check(deer.selection_weights(100)[0] == 0 and deer.selection_weights(600)[2] == 0, "Selector avoids point-blank rush and distant empty sweep")
	if DisplayServer.get_name() != "headless":
		for frame in 90: await process_frame
		for side in [-1,1]:
			for i in 4:
				reset_pair(side)
				deer.manual_control = true
				if i == 2: deer.position.x = lan.position.x-side*225
				deer.start_move(i,lan.position.x)
				for frame in 230:
					tick()
					if frame in [24,42,48,61,66,82,122,190]: await capture("duel_%d_%d_%03d" % [side,i,frame])
	reset_pair()
	deer.start_move(3,lan.position.x)
	var old := deer
	room.reset_room()
	await process_frame
	deer = room.adapter.boss
	deer.set_physics_process(false)
	check(deer != old and room.combat_simulation and not deer.manual_control, "R recreates and restarts complete phase")
	old = deer
	room.select_boss(0)
	await process_frame
	check(not is_instance_valid(old), "Switch removes duel and all its effects")
	check(room.adapter.boss.get_script().resource_path.ends_with("deer_boss.gd"), "Formal four-phase encounter is unchanged")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER DUEL CONTRACTS")

func reset_pair(facing := -1) -> void:
	room._combat_result = ""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.manual_control = false
	deer.wait_left = 99
	deer.position.x = 820 if facing < 0 else 360
	lan.reset_after_map_fall(Vector2(380 if facing < 0 else 800,555))
	lan.combat_stats.restore_health()
	lan.set_physics_process(false)
	lan.facing_direction = -facing
	contacts.clear()

func tick() -> void:
	deer._physics_process(1.0/60)
	if deer.move == &"": deer.wait_left = 99
	deer.vfx._process(1.0/60)

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

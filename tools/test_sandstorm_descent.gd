extends SceneTree
var failures := 0
var room: Node2D
var output := ""
var native := false
var results: Array = []

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func capture(name: String) -> void:
	if not native: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func start_skill(combat: bool) -> SandstormDescent:
	if room.combat_simulation: room.set_combat_simulation(false)
	room.reset_room()
	if combat: room.set_combat_simulation(true)
	else: room.play_action(SandstormFighter.COMBOS.size())
	var boss: SandstormFighter = room.adapter.boss
	boss.set_process(false)
	var skill: SandstormDescent = boss.descent
	skill.finished.disconnect(boss._on_descent_finished)
	return skill

func run() -> void:
	output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-skill")
	DirAccess.make_dir_recursive_absolute(output)
	native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280,720)
	room = load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	check(root.get_node("SaveProgress") is BossDevelopmentRoom.PreviewProgress, "Skill practice must isolate saves")
	var skill := start_skill(false)
	skill.set_physics_process(false)
	var captured := {}
	var previous := Vector2.ZERO
	var previous_phase := -1
	var health: int = room.player.combat_stats.health
	var vertical_error := 0.0
	var frames := {}
	var highest_root := INF
	for tick in 1500:
		skill.advance(1.0/120.0)
		highest_root = minf(highest_root, skill.global_position.y)
		frames[skill.shown_frame] = true
		if skill.phase == SandstormDescent.Phase.FALL and previous_phase == skill.phase:
			vertical_error = maxf(vertical_error, absf(skill.global_position.x - previous.x))
			check(skill.global_position.y >= previous.y, "Drop must never reverse upward")
		if skill.phase == SandstormDescent.Phase.IMPACT:
			check(skill.shown_frame == 9, "Touchdown must be user frame 10")
			var bottom: float = skill.config.frame_bottoms["跳跃落地"][9]
			check(absf(skill.body.to_global(Vector2(0,bottom-128)).y - room.FLOOR_Y)<0.01, "Landing feet must stay planted")
		var key := str(skill.phase)
		var frame_key := "frame_" + str(skill.shown_frame + 1)
		if skill.drop_index == 1 and skill.phase in [SandstormDescent.Phase.CHARGE, SandstormDescent.Phase.FALL, SandstormDescent.Phase.IMPACT] and not captured.has(frame_key):
			captured[frame_key] = true
			await capture(frame_key)
		if skill.drop_index == 1 and not captured.has(key) and skill.clock >= .04:
			captured[key] = true
			await capture("miss_phase_"+key)
		previous = skill.global_position
		previous_phase = skill.phase
		if skill.phase == SandstormDescent.Phase.DONE: break
	check(skill.landing_count == 5, "Manual preview must contain exactly five landings")
	check(skill.punch_count == 0, "A manual miss must not invent a tiger follow-up")
	check(vertical_error < .001, "Falling X must remain locked")
	check(absf(room.FLOOR_Y - highest_root - 420.0) < .01, "Drop height must be 420 pixels without a toolbar constraint")
	for frame in [4,5,6,7,8,9]: check(frames.has(frame), "Missing requested frame %d" % (frame+1))
	check(room.player.combat_stats.health == health, "Manual preview damaged Lan")
	results.append({"case":"preview", "landings":skill.landing_count, "punches":skill.punch_count, "vertical_x_error":vertical_error})
	for mode in ["hit", "wide", "late_hit", "dodge", "parry", "guard", "air"]:
		skill = start_skill(true)
		room.player.set_physics_process(mode in ["hit", "wide", "late_hit"])
		var contacts: Array = []
		skill.attack_hitbox.hit_resolved.connect(func(_target: Node, result: int): contacts.append({"result":result,"phase":skill.phase,"frame":skill.sample().frame,"phase_time":skill.clock}))
		var punch_captured := false
		var launch_seen := false
		var dodge_started := 0
		var slow_seen := false
		var inverted := false
		var drop_captures := {}
		var moved_wide := false
		for tick in 1600:
			if mode == "late_hit" and skill.phase == SandstormDescent.Phase.CHARGE and skill.drop_index < 3:
				room.player.global_position.x = skill.locked_x + 350
			if mode == "wide" and skill.phase == SandstormDescent.Phase.PUNCH and not moved_wide:
				moved_wide = true
				room.player.global_position.x = skill.global_position.x + skill.facing * 220
			if mode == "dodge" and skill.phase == SandstormDescent.Phase.FALL and dodge_started != skill.drop_index:
				dodge_started = skill.drop_index
				room.player.combat_stats.restore_stamina(room.player.combat_stats.max_stamina)
				room.player.start_back_dodge()
				room.player.combat_timeline.seek(.03, true)
				room.player.combat_timeline.pause()
			if mode == "parry": room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
			if mode == "guard": room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
			if mode == "air": room.player.global_position.y = room.FLOOR_Y-100
			await physics_frame
			if skill.body.visible and skill.body.global_transform.y.y < 0.0: inverted = true
			var shot := "%d_%d" % [skill.drop_index,skill.phase]
			var shot_time := .12 if skill.phase == SandstormDescent.Phase.FALL else (.35 if skill.phase == SandstormDescent.Phase.PUNCH else .10)
			if mode == "hit" and skill.phase in [SandstormDescent.Phase.CHARGE, SandstormDescent.Phase.FALL, SandstormDescent.Phase.IMPACT, SandstormDescent.Phase.PUNCH, SandstormDescent.Phase.VANISH] and skill.clock >= shot_time and not drop_captures.has(shot):
				drop_captures[shot] = true
				await capture("hit_cycle_" + shot)
			if skill.phase == SandstormDescent.Phase.PUNCH:
				check(skill.punch.document.events.is_empty() and skill.punch.effects.is_empty(), "Ground punch must not carry slash/ribbon tracks")
				if mode in ["hit", "wide"] and skill.punch_released and skill.punch.clock >= skill.punch_contact + .025 and not drop_captures.has("release"):
					drop_captures["release"] = true
					await capture("tiger_release_" + mode)
			if mode == "hit" and skill.phase == SandstormDescent.Phase.FINISH and skill.clock >= .15 and not drop_captures.has("finish"):
				drop_captures["finish"] = true
				await capture("tiger_finish")
			if skill.action_clock.is_slowed(): slow_seen = true
			if mode == "hit" and room.player.velocity.y < -100: launch_seen = true
			if mode == "hit" and skill.phase == SandstormDescent.Phase.PUNCH and skill.clock >= .35 and not punch_captured:
				punch_captured = true
				await capture("confirmed_tiger_punch")
			if skill.phase == SandstormDescent.Phase.DONE: break
		var expected_landings := 1 if mode in ["hit", "wide"] else (3 if mode == "late_hit" else 5)
		check(skill.landing_count == expected_landings, mode+": must stop drops at the confirmed-hit finisher")
		check(not inverted, mode+": body became upside down after tiger handoff")
		if mode in ["hit", "wide", "late_hit"]:
			check(skill.punch_count == 1, "One confirmed earthquake hit must end with exactly one tiger punch")
			if mode == "hit": check(launch_seen, "Earthquake must actually launch Lan")
			var tiger_hits := 0
			for contact: Dictionary in contacts:
				if contact.phase == SandstormDescent.Phase.PUNCH and contact.result == CombatHitResult.Type.NORMAL_HIT:
					tiger_hits += 1
					check(contact.phase_time >= .70, "Tiger punch must have the extended charge before contact")
					check(contact.frame >= 6, "Tiger punch cannot hit while the fist is still raised")
			check(tiger_hits == 1, "Charged tiger punch must reach Lan within its enlarged area")
		else: check(skill.punch_count == 0, mode+": non-hit cannot add tiger punch")
		if mode == "dodge": check(slow_seen, "Real dodge contact must engage the shared action clock")
		results.append({"case":mode,"landings":skill.landing_count,"punches":skill.punch_count,"contacts":contacts})
		room.player.ultimate_active = false
		room.player.set_physics_process(true)
	# Teardown while effects and a hitbox are live must discard the entire skill subtree.
	skill = start_skill(true)
	var old: Node = skill
	room.reset_room()
	await process_frame
	check(not is_instance_valid(old), "Reset leaked the old skill or its attack source")
	# Exercise the actual completion callback and automatic practice replay as well.
	var actor: SandstormFighter = room.adapter.boss
	var cycle: SandstormDescent = actor.descent
	var final_at := Vector2.ZERO
	for tick in 1000:
		if is_instance_valid(cycle): final_at = Vector2(cycle.global_position.x, room.FLOOR_Y)
		await physics_frame
		if not is_instance_valid(cycle): break
	check(not is_instance_valid(cycle), "Completed production skill must return to idle")
	check(actor.looping_idle, "Completed five-drop round must settle to idle")
	if actor.looping_idle:
		var idle_feet: Vector2 = actor.playback.to_global(actor.playback.origin)
		check(idle_feet.distance_to(final_at) < .01, "Idle return must preserve last ground position")
	for tick in 180:
		await physics_frame
		if is_instance_valid(actor.descent): break
	check(not is_instance_valid(actor.descent) and actor.looping_idle, "Tiger finisher must remain idle, not resume descents")
	print("SANDSTORM DESCENT: ", failures, " failures; ", JSON.stringify(results))
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"native":native,"cases":results},"\t"))
	root.remove_child(room)
	room.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)

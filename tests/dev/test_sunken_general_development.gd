extends "../support/harness.gd"

const General = preload("res://scripts/bosses/sunken_general/sunken_general.gd")
var room: BossDevelopmentRoom
var general: General


func run() -> void:
	use_memory_progress()
	room = preload("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await wait_frames(3)
	for index in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[index].name.contains("残甲将军"):
			room.select_boss(index)
			break
	general = room.adapter.boss as General
	check(is_instance_valid(general), "Shared catalog spawns the Sunken General")
	if general == null:
		finish("SUNKEN GENERAL DEVELOPMENT")
		return
	check(general.manual_control and room.dummy.visible and room.combat_toggle.visible, "Manual preview and real duel use the shared room")
	check(general.animated_sprite.sprite_frames.get_frame_count(General.WAVE_MOVE) == 17
		and general.animated_sprite.sprite_frames.get_frame_count(General.REVERSE) == 16, "Hand-edited source frames are loaded")

	room.dummy_x.value = 420
	room.play_action(0)
	check(await _until(func(): return general.waves.size() == 1), "First swing produces one detached sword wave")
	var wave := general.waves[0]
	check(absf(wave.velocity.x) > 300.0, "Phase-one blade snaps forward on release")
	check(wave._soul_art != null and is_zero_approx(wave.velocity.y)
		and is_equal_approx(wave.launch_position.y, BossDevelopmentRoom.FLOOR_Y - 68.0),
		"Phase-one soul sweep flies level from the measured blade tip")
	check(is_equal_approx(wave._edge(1.0).y - wave._edge(0.0).y, 404.0),
		"The whole tall crescent is active on its release frame")
	await _check_planted_pose(General.WAVE_MOVE, 12, "Extended wave finish")
	check(is_equal_approx(absf(wave.velocity.x), 96.0), "Phase-one wave settles into its slow travel")
	check(await _until(func(): return room.dummy.contacts.size() == 1, 200), "Detached wave hits the real dummy shape once")

	room.dummy_x.value = 688
	room.play_action(1)
	await _check_planted_pose(General.REVERSE, 4, "Loaded horizontal slash")
	check(await _until(func(): return room.dummy.contacts.size() == 1), "Near reverse slash uses its horizontal contact")
	check(room.player.combat_stats.health == room.player.combat_stats.max_health, "Manual mode keeps Lan safe")
	await _check_planted_pose(General.REVERSE, 15, "Low horizontal slash finish")
	check(await _until(func(): return general.animated_sprite.animation == General.RECOVER),
		"Reverse slash uses the archived closing poses")
	check(general.attack_hitbox.attack == null, "Reverse recovery stays non-damaging")

	room.play_action(2)
	var dash_start := general.global_position.x
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 5), "Dash reaches the sixth charge pose")
	check(is_equal_approx(general.global_position.x, dash_start), "All charge poses keep the same position")
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 6), "Dash completes six grounded charge poses")
	check(not general._dust.is_empty(), "The sprint leaves a floor-anchored dust wake")
	room.dummy_x.value = 540
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 15),
		"Dash reaches its braking pose")
	check(general.facing == -1.0, "Dash braking retains the sprint direction before turning")
	await _check_planted_pose(General.DASH, 15, "Dash braking")
	check(await _until(func(): return general.move == General.CHOPS), "Dash reaches its separate chop chain")
	check(absf(general.global_position.x - 588.0) < 2.0 and general.facing == 1.0, "Dash commits to its locked endpoint, then faces back")
	await _check_chop_landings()
	check(is_equal_approx(general.global_position.y, BossDevelopmentRoom.FLOOR_Y), "Last landing restores the floor line")

	room.dummy_x.value = 688
	room.play_action(3)
	var uppercut_duration := general._clock[-1]
	var uppercut_origin := general.global_position
	await _check_planted_pose(General.UPPERCUT, 6, "Uppercut draw with both feet down")
	check(await _until(func(): return not general._soul_effects.is_empty()),
		"Phase-one uppercut releases its baked rising cut")
	check(general.attack_hitbox.attack != null, "Uppercut contact and effect share a release")
	check(await _until(func(): return room.dummy.contacts.size() == 1), "Slow uppercut reaches the standing target")
	await _check_planted_pose(General.UPPERCUT, General.UPPERCUT_PLANT, "Uppercut front-foot landing")
	var uppercut_landing := general.global_position
	check(is_equal_approx(uppercut_landing.x, uppercut_origin.x + general.facing * General.UPPERCUT_SLIDE),
		"Uppercut completes one short slide by the front-foot landing")
	await _check_planted_pose(General.UPPERCUT, General.UPPERCUT_FINISH, "High-blade uppercut finish")
	check(general.global_position.is_equal_approx(uppercut_landing), "Uppercut holds its landing position through the finish")

	room.play_action(4)
	check(await _until(func(): return general._weapon_fire.visible), "Kindling visibly wraps the weapon during the stance")
	check(await _until(func(): return general.phase == 2, 140), "Kindling ends in phase two")
	check(general._weapon_fire.visible, "Fire remains attached in idle")
	room.play_action(0)
	check(await _until(func(): return general.waves.size() == 1), "Phase two launches the fire wave")
	wave = general.waves[0]
	check(is_equal_approx(absf(wave.velocity.x), 96.0), "Fire wave starts with the slow drift")
	check(await _until(func(): return is_instance_valid(wave) and not wave.is_queued_for_deletion() and absf(wave.velocity.x) >= 600.0),
		"The same fire wave accelerates beyond 600 px/s")
	check(wave._warned and wave._blade.fire, "Fire wave emits its pre-surge cue")
	check(wave._soul_art == null, "Phase two keeps its separate burning wave")
	check(wave.attack.health_damage > 16 and wave._blade.height > 260.0, "Fire phase increases damage and visible cutting height")

	room.play_action(3)
	check(await _until(func(): return general.animated_sprite.animation == General.RECOVER, 165),
		"Flaming uppercut uses the archived closing poses")
	check(general.attack_hitbox.attack == null and general._weapon_fire.visible
		and is_equal_approx(general._clock[-1], uppercut_duration), "Flaming uppercut keeps fire and the same heavy body timing")
	check(await _until(func(): return general.move == General.IDLE), "Uppercut recovery reaches the standing pose")

	room.dummy_x.value = 1244
	room.play_action(2)
	check(await _until(func(): return general.move == General.CHOPS, 135), "A wall-limited dash still reaches its follow-up")
	check(is_equal_approx(general.global_position.x, general.world_max_x) and general.facing == 1.0,
		"A dash that cannot pass the target stops inside the boundary and keeps facing it")

	room.select_combo(0)
	room.set_combat_simulation(true)
	await wait_frames(5)
	general.begin_action(General.DASH)
	check(await _until(func(): return room.player.combat_stats.health < room.player.combat_stats.max_health),
		"Real duel uses swept dash contact against Lan")
	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	await wait_frames(5)
	general.begin_action(General.DASH)
	check(await _until(func(): return general.age >= general._dash_contact_at - 0.18), "Red dash reaches its manual K window")
	_send_action(&"parry", true)
	await physics_frame
	await process_frame
	_send_action(&"parry", false)
	check(await _until(func(): return general.red_parry_hold, 25), "Real K input triggers Lan's shared red counter")
	check(general.move == General.IDLE and general.waves.is_empty(), "Red counter cancels the three-chop follow-up")

	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	room.player.reset_after_map_fall(Vector2(688.0, BossDevelopmentRoom.FLOOR_Y))
	general.begin_action(General.REVERSE)
	check(await _until(func(): return room.player.combat_stats.health < room.player.combat_stats.max_health),
		"Waiting in range takes the heavy horizontal slash")

	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	room.player.reset_after_map_fall(Vector2(688.0, BossDevelopmentRoom.FLOOR_Y))
	general.begin_action(General.REVERSE)
	check(await _until(func(): return general.action_frame == 2), "Lan can read the early draw before retreating")
	_send_action(&"ui_left", true)
	check(await _until(func(): return general.action_frame == 8), "Lan can retreat before the blade settles")
	_send_action(&"ui_left", false)
	check(room.player.global_position.x < 600.0 and room.player.combat_stats.health == room.player.combat_stats.max_health,
		"Actual movement input clears the heavy cut without taking damage")

	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	room.player.reset_after_map_fall(Vector2(688.0, BossDevelopmentRoom.FLOOR_Y))
	general.begin_action(General.UPPERCUT)
	check(await _until(func(): return room.player.combat_stats.health < room.player.combat_stats.max_health, 120),
		"The short-slide uppercut hits Lan at close range")

	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	room.player.reset_after_map_fall(Vector2(600.0, BossDevelopmentRoom.FLOOR_Y))
	general.begin_action(General.UPPERCUT)
	check(await _until(func(): return general.move == General.IDLE, 175), "Uppercut recovers while Lan stands outside the sweep")
	check(room.player.combat_stats.health == room.player.combat_stats.max_health,
		"The short slide leaves Lan safe outside the sweep")

	await _check_soul_sweep_defenses()

	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	general.combat_stats.apply_health_damage(360)
	check(await _until(func(): return general.move == General.KINDLE), "Half health automatically begins the transformation")
	check(await _until(func(): return general.phase == 2, 140), "Actual duel reaches flaming phase")
	check(general.combat_stats.health == 360 and not general.invulnerable, "Transformation resumes combat on the same health bar")

	room.reset_room()
	general = room.adapter.boss as General
	check(general.phase == 1 and general.waves.is_empty() and not general._weapon_fire.visible,
		"Retry clears prior waves and returns to the selected start phase")
	current_scene = null
	room.free()
	await wait_frames(3)
	expect_save_untouched()
	finish("SUNKEN GENERAL DEVELOPMENT")


func _until(predicate: Callable, limit := 105) -> bool:
	for _tick in limit:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _check_soul_sweep_defenses() -> void:
	var target_x := 530.0
	for response in ["stand", "parry", "jump"]:
		room.set_combat_simulation(false)
		room.set_combat_simulation(true)
		room.player.reset_after_map_fall(Vector2(target_x, BossDevelopmentRoom.FLOOR_Y))
		general.begin_action(General.WAVE_MOVE)
		if response == "jump":
			await _until(func(): return general.action_frame == 8)
			await _tap_action(&"jump")
			for tick in 23:
				await physics_frame
			await _tap_action(&"jump")
			check(room.player.global_position.y < BossDevelopmentRoom.FLOOR_Y - 70.0,
				"Lan is already in the air as the tall crescent releases")
		var launched := await _until(func(): return not general.waves.is_empty())
		check(launched, "Soul sweep launches for " + response)
		if not launched:
			continue
		var wave := general.waves[0]
		if response == "stand":
			check(await _until(func(): return room.player.combat_stats.health < room.player.combat_stats.max_health, 160),
				"Standing in the horizontal blade band takes damage")
		elif response == "parry":
			check(await _until(func(): return wave.contact_in(room.player.global_position) <= 0.10, 160),
				"Lan can wait for the travelling blade")
			await _tap_action(&"parry")
			check(await _until(func(): return general.waves.is_empty(), 25)
				and room.player.combat_stats.health == room.player.combat_stats.max_health,
				"Grounded K parries the soul sweep")
		else:
			var hit := await _until(func(): return room.player.combat_stats.health < room.player.combat_stats.max_health, 65)
			check(hit and room.player.global_position.y < BossDevelopmentRoom.FLOOR_Y - 70.0,
				"The tall edge catches Lan above the old blade band")


func _tap_action(action: StringName) -> void:
	_send_action(action, true)
	await physics_frame
	await process_frame
	_send_action(action, false)


func _check_planted_pose(action: StringName, frame: int, label: String) -> void:
	var reached := await _until(func(): return general.move == action and general.action_frame == frame, 180)
	check(reached, label + " reaches the chosen pose")
	if not reached:
		return
	var origin := general.global_position
	var direction := general.facing
	var drift := 0.0
	var turned := false
	while general.move == action and general.action_frame == frame:
		drift = maxf(drift, general.global_position.distance_to(origin))
		turned = turned or general.facing != direction
		await physics_frame
	check(drift < 0.1 and not turned, label + " holds its footprint and facing")


func _check_chop_landings() -> void:
	var emitted := {}
	for _tick in 240:
		if general.move != General.CHOPS:
			break
		for projectile in general.waves:
			var id := projectile.get_instance_id()
			if emitted.has(id):
				continue
			emitted[id] = projectile._blade.height
			check(is_equal_approx(general.global_position.y, BossDevelopmentRoom.FLOOR_Y),
				"Chop wave is released on the grounded pose")
		await physics_frame
	var heights := emitted.values()
	check(heights.size() == 3 and heights[0] < heights[1] and heights[1] < heights[2],
		"Three separate landings emit three progressively larger waves")
	check(general.move == General.IDLE, "Three jumps land and return to idle")


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

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
	check(is_equal_approx(absf(wave.velocity.x), 96.0), "Phase-one wave moves slowly")
	check(await _until(func(): return room.dummy.contacts.size() == 1, 200), "Detached wave hits the real dummy shape once")

	room.dummy_x.value = 688
	room.play_action(1)
	check(await _until(func(): return room.dummy.contacts.size() == 1), "Near reverse slash uses its horizontal contact")
	check(room.player.combat_stats.health == room.player.combat_stats.max_health, "Manual mode keeps Lan safe")

	room.play_action(2)
	var dash_start := general.global_position.x
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 5), "Dash reaches the sixth charge pose")
	check(is_equal_approx(general.global_position.x, dash_start), "All charge poses keep the same position")
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 6), "Dash completes six grounded charge poses")
	check(not general._dust.is_empty(), "The sprint leaves a floor-anchored dust wake")
	room.dummy_x.value = 540
	check(await _until(func(): return general.move == General.CHOPS), "Dash reaches its separate chop chain")
	check(absf(general.global_position.x - 588.0) < 2.0 and general.facing == 1.0, "Dash commits to its locked endpoint, then faces back")
	check(await _until(func(): return general.waves.size() == 3, 145), "Three chop contacts launch exactly three waves")
	var heights: Array[float] = []
	for projectile in general.waves:
		heights.append(projectile._blade.height)
	check(heights.size() == 3 and heights[0] < heights[1] and heights[1] < heights[2], "Chop wave heights increase at each release")
	check(await _until(func(): return general.move == General.IDLE), "Three jumps land and return to idle")
	check(is_equal_approx(general.global_position.y, BossDevelopmentRoom.FLOOR_Y), "Last landing restores the floor line")

	room.dummy_x.value = 688
	room.play_action(3)
	check(await _until(func(): return is_instance_valid(general._uppercut_vfx)), "Uppercut has a separate rising crescent")
	check(general.attack_hitbox.attack != null, "Uppercut contact and effect share a release")
	check(await _until(func(): return room.dummy.contacts.size() == 1), "Slow uppercut reaches the standing target")

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
	check(wave.attack.health_damage > 16 and wave._blade.height > 260.0, "Fire phase increases damage and visible cutting height")

	room.dummy_x.value = 1244
	room.play_action(2)
	check(await _until(func(): return general.move == General.CHOPS), "A wall-limited dash still reaches its follow-up")
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
	_send_parry(true)
	await physics_frame
	await process_frame
	_send_parry(false)
	check(await _until(func(): return general.red_parry_hold, 25), "Real K input triggers Lan's shared red counter")
	check(general.move == General.IDLE and general.waves.is_empty(), "Red counter cancels the three-chop follow-up")

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


func _send_parry(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"parry"
	event.pressed = pressed
	Input.parse_input_event(event)

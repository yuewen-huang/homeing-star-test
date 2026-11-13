extends "../support/harness.gd"

const General = preload("res://scripts/bosses/sunken_general/sunken_general.gd")
const Kindling = preload("res://scripts/bosses/sunken_general/sunken_general_kindling.gd")
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
	var reverse_clock := general._clock.duplicate()
	check(await _until(func(): return not general._soul_effects.is_empty()),
		"Phase-one reverse slash releases its baked blade and smoke")
	var reverse_art = general._soul_effects[0]
	var reverse_atlas: Texture2D = reverse_art.texture
	var reverse_duration: float = reverse_art.duration
	var reverse_scale: Vector2 = reverse_art.scale
	var reverse_offset: Vector2 = reverse_art.offset
	var reverse_frame := general.action_frame
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
	check(general._soul_effects.size() == 2, "Phase-one dash releases its blade and smoke together")
	if general._soul_effects.size() == 2:
		var wake: Sprite2D = general._soul_effects[0]
		var head: Sprite2D = general._soul_effects[1]
		await physics_frame
		await physics_frame
		check(wake.top_level and is_equal_approx(wake.global_position.x, dash_start)
			and not head.top_level and is_equal_approx(head.global_position.x, general.global_position.x),
			"The smoke stays on the crossed ground and the blade follows the sprint")
	room.dummy_x.value = 540
	check(await _until(func(): return general.move == General.DASH and general.action_frame == 15),
		"Dash reaches its braking pose")
	check(general.facing == -1.0, "Dash braking retains the sprint direction before turning")
	check(not general._soul_effects.is_empty(), "The dash smoke continues into the braking pose")
	await _check_planted_pose(General.DASH, 15, "Dash braking")
	check(await _until(func(): return general.move == General.CHOPS), "Dash reaches its separate chop chain")
	check(general._soul_effects.is_empty(), "The old dash effects clear at the turn into the chops")
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
	var hold_start: float = general._clock[Kindling.HOLD_FRAME]
	var hold_end: float = general._clock[Kindling.HOLD_FRAME + 1]
	check(is_equal_approx(hold_end - hold_start, 2.45), "Kindling holds the single-handed pose for 2.45 seconds")
	check(await _until(func(): return general._kindling._front.is_visible_in_tree()), "Fire begins on the body")
	check(general.action_frame < Kindling.HOLD_FRAME and not general._kindling.weapon_fire.visible
		and not general._kindling._draw_in.visible, "The body catches fire before the blade draws it in")
	check(await _until(func(): return general._kindling._draw_in.is_visible_in_tree(), 65), "Fire draws into the weapon when the pose is held")
	check(general.action_frame == Kindling.HOLD_FRAME and not general._kindling._roared, "The draw precedes the roar")
	check(await _until(func(): return general._kindling.weapon_fire.is_visible_in_tree(), 30)
		and not general._kindling._shaft_fire.visible, "Blade lights before the shaft")
	check(await _until(func(): return general._kindling._shaft_fire.is_visible_in_tree(), 55)
		and general._kindling._shaft_fire.region_rect.size.x < Kindling.SHAFT_CELL.x
		and not general._kindling._roared, "Shaft fire spreads from the blade before the roar")
	check(await _until(func(): return general._kindling._erupted, 115), "The fire erupts after the weapon charges")
	check(general._kindling._roared and general._kindling._voice.playing and general._kindling.weapon_fire.visible
		and not general._kindling._front.visible, "The roar and blast play together with the enchanted blade")
	check(general.action_frame == Kindling.HOLD_FRAME and general.attack_hitbox.attack == null,
		"The eruption plays on the held pose without opening a damage window")
	check(await _until(func(): return general.phase == 2, 125), "Kindling ends in phase two")
	check(not general._kindling._burst.visible and not general._kindling._voice.playing, "Temporary fire and the roar clear at handoff")
	check(general._kindling.weapon_fire.is_visible_in_tree(), "Fire remains attached in idle")
	check(general._kindling._shaft_fire.is_visible_in_tree()
		and general._kindling._shaft_fire.region_rect.size == Kindling.SHAFT_CELL, "The full shaft stays lit in phase two")
	room.play_action(0)
	check(await _until(func(): return general.waves.size() == 1), "Phase two launches the fire wave")
	wave = general.waves[0]
	check(is_equal_approx(absf(wave.velocity.x), 96.0), "Fire wave starts with the slow drift")
	check(await _until(func(): return is_instance_valid(wave) and not wave.is_queued_for_deletion() and absf(wave.velocity.x) >= 600.0),
		"The same fire wave accelerates beyond 600 px/s")
	check(wave._warned and wave._soul_art.material is ShaderMaterial and wave._continuous_wake,
		"Fire wave emits its pre-surge cue with the continuous wake")
	check(wave._heat_tail.is_visible_in_tree(), "Traveling fire wave carries localized heat haze")
	check(wave.attack.health_damage > 16 and is_equal_approx(wave._edge(1.0).y - wave._edge(0.0).y, 312.0)
		and wave._soul_art.texture == wave.SOUL_SHEET, "Fire wave keeps its hit geometry and uses the first-phase atlas")

	room.play_action(3)
	check(await _until(func(): return _has_fire("rise")), "Flaming uppercut releases the rising fire wall")
	check(await _until(func(): return general.animated_sprite.animation == General.RECOVER, 165),
		"Flaming uppercut uses the archived closing poses")
	check(general.attack_hitbox.attack == null and general._kindling.weapon_fire.is_visible_in_tree()
		and is_equal_approx(general._clock[-1], uppercut_duration), "Flaming uppercut keeps fire and the same heavy body timing")
	check(await _until(func(): return general.move == General.IDLE), "Uppercut recovery reaches the standing pose")
	check(general._ground_fires.size() == 1 and general._ground_fires[0].active(),
		"The phase-two uppercut leaves ground fire after returning to idle")

	room.dummy_x.value = 688
	room.play_action(1)
	var reverse_released := await _until(func(): return _has_fire("reverse"))
	check(reverse_released, "Phase two releases a wide reverse fire slash")
	if reverse_released:
		reverse_art = general._soul_effects[0]
		check(general._clock == reverse_clock and general.action_frame == reverse_frame
			and reverse_art.texture == reverse_atlas and reverse_art.duration == reverse_duration
			and reverse_art.scale == reverse_scale and reverse_art.offset == reverse_offset,
			"Both phases use the same reverse slash atlas, geometry and action timing")
		check(reverse_art.material.shader.resource_path.ends_with("reverse_fire.gdshader")
			and is_equal_approx(reverse_art._haze_strength, 0.27),
			"The reverse slash uses the Studio flame palette and subtle heat haze")
	room.dummy_x.value = 1244
	room.play_action(2)
	check(await _until(func(): return _has_fire("dash") and _has_fire("dash_wake")),
		"Phase-two dash releases the moving fire blade and floor wake")
	check(await _until(func(): return general.move == General.CHOPS, 135), "A wall-limited dash still reaches its follow-up")
	check(not _has_fire("dash") and not _has_fire("dash_wake"), "Dash flames clear before the boss turns")
	check(is_equal_approx(general.global_position.x, general.world_max_x) and general.facing == 1.0,
		"A dash that cannot pass the target stops inside the boundary and keeps facing it")
	var last_size := 0.0
	for index in General.CHOP_ARCS.size():
		var land: int = General.CHOP_ARCS[index].land
		check(await _until(func(): return general.move == General.CHOPS and general.action_frame == land - 2)
			and _has_fire("chop"), "Phase-two chop %d has an air cut" % (index + 1))
		var landed := await _until(func(): return general.action_frame == land and not general.waves.is_empty())
		check(landed, "Phase-two chop %d releases a ground wave" % (index + 1))
		if landed:
			wave = general.waves.back()
			var ground_fire = wave._blade._chop_quake
			var boundary: float = wave.world_max_x if wave.velocity.x > 0.0 else wave.world_min_x
			var distance := minf(wave.life * 560.0, absf(boundary - wave.launch_position.x))
			check(ground_fire.spec.form == "guandao_wave" and ground_fire.spec.trail == "flame"
				and float(ground_fire.spec.unit_size) > last_size and is_equal_approx(absf(wave.velocity.x), 560.0)
				and is_equal_approx(absf(ground_fire.scale.y), 1.5)
				and is_equal_approx(ground_fire.reach() * absf(ground_fire.scale.x), distance),
				"Phase-two chop %d uses the flame trail with a larger blade at the original speed" % (index + 1))
			last_size = float(ground_fire.spec.unit_size)

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
	check(general._soul_effects.is_empty(), "Red counter clears both sprint layers immediately")

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
	await _check_uppercut_ground_fire()

	room.select_combo(0)
	room.set_combat_simulation(false)
	room.set_combat_simulation(true)
	general.combat_stats.apply_health_damage(360)
	check(await _until(func(): return general.move == General.KINDLE), "Half health automatically begins the transformation")
	check(await _until(func(): return general.phase == 2, 270), "Actual duel reaches flaming phase")
	check(general.combat_stats.health == 360 and not general.invulnerable, "Transformation resumes combat on the same health bar")

	room.set_combat_simulation(false)
	room.play_action(4)
	check(await _until(func(): return general._kindling._roared, 155), "Retry fixture reaches the roar")
	room.reset_room()
	general = room.adapter.boss as General
	check(general.phase == 1 and general.waves.is_empty() and not general._kindling.weapon_fire.visible,
		"Retry clears prior waves and returns to the selected start phase")
	check(not general._kindling.visible and not general._kindling._voice.playing, "Retry stops the transformation fire and roar")
	check(not general._kindling._shaft_fire.visible, "Retry clears shaft fire")
	current_scene = null
	room.free()
	await wait_frames(3)
	expect_save_untouched()
	finish("SUNKEN GENERAL DEVELOPMENT")


func _has_fire(form: String) -> bool:
	return general._soul_effects.any(func(art: Sprite2D) -> bool: return art.fire_form == form)


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


func _check_uppercut_ground_fire() -> void:
	const FLOOR := BossDevelopmentRoom.FLOOR_Y
	var player := room.player
	room.set_combat_simulation(false)
	room.select_combo(1)
	room.set_combat_simulation(true)
	player.reset_after_map_fall(Vector2(130.0, FLOOR))
	general.begin_action(General.UPPERCUT)
	var spawned := await _until(func(): return not general._ground_fires.is_empty(), 100)
	check(spawned, "Real phase-two uppercut creates a separate ground hazard")
	if not spawned:
		return
	var fire := general._ground_fires[0]
	check(not fire.active(), "Ground fire starts when the front foot plants")
	check(await _until(fire.active, 20), "The patch ignites during the rising cut")
	var full_width := fire.active_width()
	check(is_equal_approx(full_width, 1020.0) and player.combat_stats.health == player.combat_stats.max_health,
		"The fire starts at the full floor width of the wave and leaves its outside edge safe")
	var fire_position := fire.global_position
	await _until(func(): return general.action_frame == General.UPPERCUT_CONTACT_END, 55)
	# Leave room for the jump, then enter the center while already in the air.
	player.reset_after_map_fall(Vector2(130.0, FLOOR))
	await _tap_action(&"jump")
	await wait_frames(12)
	player.global_position.x = fire_position.x
	await wait_frames(3)
	check(player.global_position.y < FLOOR - 20.0
		and absf(player.global_position.x - fire_position.x) < fire.active_width() * 0.5
		and player.combat_stats.health == player.combat_stats.max_health,
		"Airborne Lan above the fire stays safe after a real jump")
	await _until(func(): return general.move == General.IDLE, 85)
	general._next_action_in = 99.0
	var landed := await _until(func(): return absf(player.global_position.y - FLOOR) <= 1.0, 75)
	var burned := await _until(func(): return player.combat_stats.health < player.combat_stats.max_health, 8)
	check(landed and burned and player.combat_stats.health == player.combat_stats.max_health - General.GROUND_FIRE_DAMAGE,
		"Landing on the fire takes one burn tick")
	var after_first := player.combat_stats.health
	await wait_frames(12)
	check(player.combat_stats.health == after_first, "Burn damage has a cooldown")
	check(await _until(func(): return player.combat_stats.health < after_first, 30),
		"Remaining on the fire causes another tick")
	var edge_x := fire_position.x - full_width * 0.5 + 35.0
	check(fire.active() and fire.active_width() < full_width * 0.65,
		"The hot zone recedes from both ends while its center is still burning")
	player.reset_after_map_fall(Vector2(edge_x, FLOOR))
	var after_retreat := player.combat_stats.health
	await wait_frames(35)
	check(player.combat_stats.health == after_retreat,
		"The original outer edge becomes safe as the fire withdraws")
	check(await _until(func(): return general._ground_fires.is_empty(), 100),
		"The fire clears itself after burning")
	var after_extinction := player.combat_stats.health
	await wait_frames(38)
	check(player.combat_stats.health == after_extinction, "Standing on the cooled patch is safe")

	room.set_combat_simulation(false)
	room.select_combo(1)
	room.play_action(3)
	check(await _until(func(): return not general._ground_fires.is_empty() and general._ground_fires[0].active(), 100),
		"Ground fire is visible in manual preview")
	room.reset_room()
	general = room.adapter.boss as General
	check(general._ground_fires.is_empty(), "Retry clears the ground fire immediately")


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

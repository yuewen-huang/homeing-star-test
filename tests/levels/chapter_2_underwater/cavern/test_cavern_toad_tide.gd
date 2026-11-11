extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TOAD := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_bronze_toad.gd")

var level: SunkenCavern


func run() -> void:
	var save := use_memory_progress()
	save.try_complete_fact(&"sunken_cavern_bell_awake")
	_load_cavern()
	var tide := level.tide
	var toad := level.bronze_toad
	var player := level.player
	player.reset_after_map_fall(Vector2(5648, TOAD.ORIGIN.y))
	level.snap_camera()
	await physics_frame
	tide.time = tide.CALM - TOAD.WELL_WINDUP
	await _advance_to(tide.CALM - 0.31)
	check(toad._well_pose_active and toad._rig.sole_at().y < TOAD.ORIGIN.y - 100.0
		and level.drips._pressure == 0.0, "the living guard raises the actual hammer before the first warning")
	await _capture("01_well_hammer_raised")

	var shakes: Array[float] = []
	var pressures: Array[float] = []
	for beat in 3:
		await _advance_to(tide.HAMMER_CONTACTS[beat] + 0.045)
		check(toad._presentation._pulses.size() == 1 and toad._rig.sole_at().y > TOAD.ORIGIN.y - 3.0,
			"hammer %d lands on stone and plays one contact splash" % (beat + 1))
		check(tide.is_surging() == (beat == 2), "only the third hammer starts the eruption")
		if beat < 2:
			check(tide.flood.column_wet.is_empty() and tide.flood.jets.all(
				func(jet: Dictionary) -> bool: return jet.wet.is_empty()),
				"warning %d keeps the deck down and the currents harmless" % (beat + 1))
		shakes.append(level.camera.offset.length())
		pressures.append(level.drips._pressure)
		await _capture("0%d_well_hammer_contact" % (beat + 2))
	check(pressures[0] > 0.0 and pressures[1] >= pressures[0] and shakes[1] > shakes[0] * 1.5,
		"first contact increases cave drips and the second shakes harder")
	await _advance_to(tide.HAMMER_CONTACTS[2] + 0.45)
	check(not tide.flood.column_wet.is_empty() and tide.deck.position.y < TOAD.ORIGIN.y - 100.0,
		"the third contact raises the timber on the real water column")
	await _capture("05_well_column")

	player.reset_after_map_fall(TOAD.ORIGIN + Vector2(-335.0, 0.0))
	await physics_frame
	await physics_frame
	check(toad.engaged and not tide.is_surging() and tide.flood.column_wet.is_empty(),
		"entering the boss fight clears an active map eruption")
	toad.combat_stats.apply_health_damage(toad.combat_stats.max_health)
	player.reset_after_map_fall(TOAD.ORIGIN + Vector2(-120.0, 0.0))
	for i in 40: await physics_frame
	check(save.has_completed(TOAD.DEFEATED) and toad.is_visible_in_tree()
		and toad._rig.scale.is_equal_approx(Vector2.ONE * TOAD.ART_SCALE * 0.5)
		and toad._blocker.disabled and (toad.get_node("Hurtbox") as Area2D).collision_layer == 0,
		"victory leaves a half-scale peaceful guard and removes its collisions")
	await _press_e()
	check(not tide._manual_active and not toad._well_hint.visible, "E outside the guard's reach does nothing")
	var blocker_x := TOAD.ORIGIN.x + TOAD.BODY_SOLID.position.x
	Input.action_press(&"ui_right")
	for i in 150:
		if player.position.x > blocker_x + 16.0: break
		await physics_frame
	Input.action_release(&"ui_right")
	check(player.position.x > blocker_x and toad._well_hint.visible,
		"real movement crosses the former blocker and finds the E prompt (x=%.1f)" % player.position.x)
	await _capture("06_well_defeated_interaction")
	await _press_e()
	check(tide._manual_active and not toad._well_hint.visible, "real E starts one cycle and consumes the prompt")
	var before := tide.time
	await _press_e()
	check(tide.time > before, "a second E cannot restart an active cycle")
	Input.action_press(&"ui_left")
	for i in 160:
		if player.position.x <= tide.deck.get_center().x: break
		await physics_frame
	Input.action_release(&"ui_left")
	check(absf(player.position.x - tide.deck.get_center().x) < 35.0 and not tide.is_surging(),
		"Lan can run from the guard to the deck during the manual warning (x=%.1f)" % player.position.x)
	var health := player.combat_stats.health
	await _advance_to(tide.HAMMER_CONTACTS[2] + tide.W1_ARRIVAL + 0.1)
	check(absf(player.position.y - level.marker("c60").y) < 1.0 and player.combat_stats.health == health,
		"the manual eruption safely carries Lan to the W1 dock")
	await _capture("07_well_manual_dock")
	tide.time = tide.CALM + tide.WARNING + tide.SURGE + tide.TAIL - 0.03
	for i in 5: await physics_frame
	check(tide.time == 0.0 and not tide._manual_active and tide.flood.column_wet.is_empty(),
		"manual cycle drains and returns to idle")
	tide._physics_process(tide.CALM + tide.WARNING + 1.0)
	check(tide.time == 0.0 and not tide.is_surging(), "defeated guard stays idle beyond the old automatic interval")
	player.reset_after_map_fall(TOAD.ORIGIN + Vector2(-8.0, 0.0))
	await _press_e()
	check(tide._manual_active, "E is available again after the well has drained")

	level.queue_free()
	await process_frame
	save = use_memory_progress()
	save.try_complete_fact(TOAD.DEFEATED)
	_load_cavern()
	check(level.bronze_toad.is_visible_in_tree() and level.bronze_toad._blocker.disabled
		and level.bronze_toad._rig.scale.is_equal_approx(Vector2.ONE * TOAD.ART_SCALE * 0.5)
		and not level.resonance.awake, "old victory saves load the small guard without depending on the bell fact")
	level.player.reset_after_map_fall(TOAD.ORIGIN + Vector2(-8.0, 0.0))
	await _press_e()
	check(level.tide._manual_active and level.tide.time > level.tide.CALM - TOAD.WELL_WINDUP,
		"an old victory save can start a manual cycle")
	level.queue_free()
	await process_frame
	expect_save_untouched()
	finish("A11 TOAD WATER COLUMN")


func _load_cavern() -> void:
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level


func _advance_to(at: float) -> void:
	for i in 600:
		if level.tide.time >= at: return
		await physics_frame
	check(false, "tide clock reaches %.2f" % at)


func _press_e() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	await physics_frame
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	Input.parse_input_event(release)
	await physics_frame


func _capture(name: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")

class FailableProgress extends MemoryProgress:
	var refuse := false
	func save_progress() -> bool: return not refuse


func run() -> void:
	var previous := use_memory_progress()
	root.remove_child(previous)
	previous.free()
	var save := FailableProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var level := SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	await physics_frame
	var puzzle := level.resonance
	level.player.set_physics_process(false)
	level.stone_lion.set_physics_process(false)
	level.tide.set_physics_process(false)
	check(not puzzle.ring_near_player() and not puzzle.awake, "bell requires proximity")
	level.player.position = level.marker("bell_top")
	save.refuse = true
	check(puzzle.ring_near_player() and not puzzle.awake, "failed bell save leaves the map asleep")
	save.refuse = false
	puzzle._physics_process(1.01)
	check(puzzle.ring_near_player() and puzzle.awake and save.has_completed(puzzle.BELL_AWAKE), "a successful bell interaction persists and wakes the map")
	level.player.position = puzzle.echoes.archive + Vector2(0, 32)
	puzzle._physics_process(0.02)
	check(not puzzle.echo_available("archive") and not puzzle.collected.has("archive"),
		"the archive fragment cannot be collected before the sound wave arrives")
	level.player.position = level.marker("bell_top")
	for i in 122: await physics_frame
	check(puzzle.echo_available("archive") and puzzle._echo_lights["archive"].visible,
		"arrival opens the archive pickup window and displays its light wave")
	check(not puzzle.echo_available("sealed_street"), "the same wave cannot expose A17 behind the intact wall")
	for i in 198: await physics_frame
	level.player.position = puzzle.echoes.archive + Vector2(0, 32)
	puzzle._physics_process(0.02)
	check(not puzzle._echo_lights["archive"].visible and not puzzle.collected.has("archive"),
		"the expired window hides the light and prevents collection beside the fragment")
	save.refuse = true
	for i in ceili((puzzle.RETURN_INTERVAL + 2.0) * 60.0):
		await physics_frame
		if puzzle.echo_available("archive") and puzzle._retry_left > 0.0: break
	check(puzzle.echo_available("archive") and not puzzle.seal_open(), "failed save leaves the echo and gate intact")
	save.refuse = false
	puzzle._physics_process(0.71)
	level.player.position = puzzle.echoes.vault + Vector2(0, 32)
	for i in 10: await physics_frame
	check(puzzle.collected.size() == 2 and not puzzle.seal_open(), "two distinct echoes keep the altar blocked")
	await check_lion_intro(level, save)
	await check_lion(level, save)
	level.player.position = puzzle.echoes.sealed_street + Vector2(0, 32)
	puzzle._physics_process(0.02)
	check(not puzzle.collected.has("sealed_street"), "breaking A17 does not create a pickup window by itself")
	for i in ceili((puzzle.RETURN_INTERVAL + 2.0) * 60.0):
		await physics_frame
		if puzzle.seal_open(): break
	await process_frame
	check(puzzle.seal_open() and puzzle._seal_shape.disabled, "third echo opens the physical seal")
	level.queue_free()
	await process_frame
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	check(level.resonance.awake and level.resonance.seal_open() and level.resonance._seal_shape.disabled,
		"reentry restores the bell and the derived seal")
	check(level.stone_lion.broken and level.stone_lion._wall_shape.disabled, "reentry restores the open A17 wall")
	check(is_zero_approx(level.tide.time), "a loaded tide starts calm rather than restoring an old countdown")
	await check_tide(level)
	await check_dry_attempts(level)
	level.queue_free()
	await process_frame
	expect_save_untouched()
	finish("CAVERN MECHANISMS")


func check_lion(level: SunkenCavern, save: FailableProgress) -> void:
	var lion := level.stone_lion
	var player := level.player
	prepare_charge(level)
	var health := player.combat_stats.health
	lion._charge(0.18)
	check(player.combat_stats.health < health and lion.state == lion.State.RECOVER and not lion.broken,
		"a genuine player collision stops the lion before the lock")
	prepare_charge(level)
	player.start_parry()
	lion._charge(0.18)
	check(player.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS and lion.state == lion.State.RECOVER,
		"normal combat parry stops the committed charge")
	prepare_charge(level)
	player.start_back_dodge(1.0)
	lion._charge(0.18)
	check(lion.state == lion.State.CHARGE and lion._contacted, "a real dodge lets the same charge continue")
	save.refuse = true
	lion._charge(0.42)
	lion._advance_lock(0.35)
	check(not lion.broken and not lion._wall_shape.disabled and not save.has_completed(lion.WALL_BROKEN),
		"a failed wall save retains the solid wall")
	lion._advance_lock(1.1)
	save.refuse = false
	prepare_charge(level)
	player.start_back_dodge(1.0)
	lion._charge(0.18)
	lion._charge(0.42)
	lion._advance_lock(0.35)
	await process_frame
	check(lion.broken and lion._wall_shape.disabled and save.has_completed(lion.WALL_BROKEN),
		"one uninterrupted lock strike opens and persists A17")


func check_lion_intro(level: SunkenCavern, save: FailableProgress) -> void:
	var lion := level.stone_lion
	var player := level.player
	player.set_physics_process(true)
	lion.set_physics_process(true)
	player.reset_after_map_fall(Vector2(4935, 3582))
	await physics_frame
	check(not lion.wake_near_player() and lion.state == lion.State.DORMANT and not lion._lion_hint_anchor.visible,
		"approach and early interaction leave the statue asleep")

	player.reset_after_map_fall(Vector2(5550, 3582))
	level.snap_camera()
	for i in 5: await physics_frame
	check(lion._hammer_hint_anchor.visible, "the visible hammer shows its J keycap")
	await strike_hammer()
	check(not is_instance_valid(lion._hammer_dialogue) and not lion.hammer_inspected,
		"a real J swing that misses the hammer does not open the dialogue")

	player.reset_after_map_fall(Vector2(5816, 3582))
	player.facing_direction = 1.0
	level.snap_camera()
	for i in 5: await physics_frame
	await strike_hammer()
	check(is_instance_valid(lion._hammer_dialogue) and player.input_frozen and not lion.broken
		and not lion._hammer_hint_anchor.visible and not lion.hammer_inspected,
		"the first real hammer contact opens the dialogue without opening A17")
	if is_instance_valid(lion._hammer_dialogue):
		lion._hammer_dialogue.advance()
	check(lion.hammer_inspected and save.has_completed(lion.HAMMER_INSPECTED)
		and not player.input_frozen and not lion.wake_near_player(),
		"finishing dialogue records the clue but distant E does not wake the lion")

	player.reset_after_map_fall(Vector2(4935, 3582))
	for i in 2: await physics_frame
	check(lion._lion_hint_anchor.visible, "the new E keycap appears within reach of the stone lion")
	save.refuse = true
	check(lion.wake_near_player() and lion.state == lion.State.DORMANT,
		"an activation save failure leaves the stone lion available to retry")
	save.refuse = false
	check(lion.wake_near_player() and save.has_completed(lion.LION_AWAKE)
		and lion.state == lion.State.APPEARING and not lion._lion_hint_anchor.visible,
		"only nearby E advances the statue to its wake-up animation")
	player.set_physics_process(false)
	lion.set_physics_process(false)


func strike_hammer() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_J
	event.physical_keycode = KEY_J
	event.pressed = true
	Input.parse_input_event(event)
	for i in 3: await physics_frame
	event.pressed = false
	Input.parse_input_event(event)
	for i in 75: await physics_frame


func prepare_charge(level: SunkenCavern) -> void:
	var lion := level.stone_lion
	var player := level.player
	player.combat_stats.restore_health()
	player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
	player.reset_after_map_fall(Vector2(5800, 3582))
	lion.position.x = 5520
	lion.facing = 1.0
	lion._set_state(lion.State.PATROL)
	lion._physics_process(0.02)
	lion._physics_process(0.91)


func check_tide(level: SunkenCavern) -> void:
	var player := level.player
	var tide := level.tide
	await physics_frame
	player.reset_after_map_fall(level.start)
	tide.time = tide.CALM + 0.25
	await physics_frame
	await physics_frame
	check(level.drips._pressure > 0.4 and level.camera.offset.length() > 0.0,
		"the remote entrance receives the same falling water and tremor as the well")
	check(tide.flood.jets.all(func(jet: Dictionary): return jet.wet.is_empty()),
		"the visible warning has no damaging current")
	player.reset_after_map_fall(Vector2(5824, 4990))
	player.set_input_frozen(true)
	await physics_frame
	var frozen_time := tide.time
	for i in 12: await physics_frame
	check(is_equal_approx(tide.time, frozen_time), "input freeze holds the water-cycle clock")
	player.set_input_frozen(false)
	tide.time = tide.CALM + tide.WARNING - 0.01
	var top := player.position.y
	var w1_dock := false
	var street_dock := false
	var health := player.combat_stats.health
	for i in 720:
		await physics_frame
		top = minf(top, player.position.y)
		w1_dock = w1_dock or absf(player.position.y - 3966.0) < 1.0
		street_dock = street_dock or absf(player.position.y - 3582.0) < 1.0
	check(top < 450.0 and w1_dock and street_dock and level.drowned_count == 0
		and not player.is_in_deep_water() and player.combat_stats.health == health,
		"the timber deck carries Lan safely from the bottom to both docks and the crown")
	player.reset_after_map_fall(Vector2(5535, 4720))
	var rose := false
	for i in 25:
		await physics_frame
		rose = rose or player.position.y < 4720.0
	check(not rose, "entering the water below the deck never lifts Lan")
	check(player.combat_stats.health < health, "the water column itself damages Lan")
	var west := Vector2(4160, 2558)
	player.reset_after_map_fall(west)
	tide.time = tide.CALM + tide.WARNING + tide.JET_START + 0.03
	health = player.combat_stats.health
	for i in 15: await physics_frame
	check(player.position.distance_to(west) < 2.0 and player.combat_stats.health == health,
		"the west street stays safe ahead of the visible front")
	for location in [west, Vector2(6800, 2814), Vector2(4160, 3070), Vector2(6800, 2302)]:
		tide.time = tide.CALM + tide.WARNING + tide.SURGE + tide.TAIL - 0.01
		await physics_frame
		await physics_frame
		tide.time = tide.CALM + tide.WARNING + tide.JET_START + 2.0
		player.reset_after_map_fall(location)
		health = player.combat_stats.health
		for i in 42 if location.y == 3070.0 else 18: await physics_frame
		check(player.combat_stats.health < health and player.position.distance_to(location) > 10.0,
			"the broad flow floods and pushes the exposed landing at %s (damage=%s, displacement=%.1f)"
			% [location, health - player.combat_stats.health, player.position.distance_to(location)])
	for location in [Vector2(5330, 3582), Vector2(7360, 2814)]:
		player.reset_after_map_fall(location)
		health = player.combat_stats.health
		for i in 24: await physics_frame
		check(absf(player.position.x - location.x) < 2.0 and player.combat_stats.health == health,
			"real terrain keeps the sheltered landing dry at %s" % location)
	check(level.open_shortcut("S2"), "the player can open the eastern shelter gate")
	tide.time = tide.CALM + tide.WARNING + tide.SURGE + tide.TAIL - 0.01
	await physics_frame
	await physics_frame
	player.reset_after_map_fall(Vector2(7360, 2814))
	tide.time = tide.CALM + tide.WARNING + tide.JET_START + 1.0
	health = player.combat_stats.health
	for i in 18: await physics_frame
	check(player.combat_stats.health < health, "opening S2 extends the real current into the former shelter")
	var stream: Dictionary = tide.flood.jets[0]
	tide.time = tide.CALM + tide.WARNING + tide.JET_START + tide.flood.RETREAT_AT - 0.08
	await physics_frame
	await physics_frame
	var spread := flooded_area(stream.wet)
	tide.time += 1.05
	await physics_frame
	await physics_frame
	check(spread > 0.0 and flooded_area(stream.wet) < spread * 0.72 and stream.push < 0.0,
		"retreat pulls the current back into the shaft and dries most of the street")


func flooded_area(strips: Array) -> float:
	var total := 0.0
	for strip: Rect2 in strips: total += strip.get_area()
	return total


func check_dry_attempts(level: SunkenCavern) -> void:
	var player := level.player
	var crossed := false
	for timing in [[15, 30], [20, 36], [25, 43]]:
		level.tide.time = 0.0
		player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
		player.reset_after_map_fall(level.marker("c20") + Vector2(26, 0))
		await physics_frame
		Input.action_press(&"ui_right")
		for frame in 140:
			if frame in [0, timing[0]] or (frame > 50 and frame % 10 == 0 and player.is_on_wall()):
				Input.action_press(&"jump")
			else: Input.action_release(&"jump")
			if frame == timing[1]: Input.action_press(&"instant_dash")
			else: Input.action_release(&"instant_dash")
			await physics_frame
			if player.position.x >= 6400 and player.position.y <= 1278: crossed = true
		for action in [&"ui_right", &"jump", &"instant_dash"]: Input.action_release(action)
	check(not crossed, "three calm-state jump, air dash and wall-contact attempts cannot reach the archive")

extends "test_sunken_cavern_graybox.gd"
## Bell, timber deck, real swim, lion lure and altar on one uninterrupted input route.


func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_gameplay_route")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	nav_links = level.layout.navigation.links.filter(func(link: Dictionary): return link.mode != "lift")
	await step(20)
	check(level.layout.ladders.size() == 8 and level.layout.water.size() == 2,
		"A11 sheds its three old ladders, retains two pools and has one dry service return")
	if not await navigate("w18") or not await navigate("bell_top"):
		await end_test()
		return
	await interact()
	check(level.resonance.awake, "A6 responds to real E input on the bell landing")
	await capture("bell_rings")
	if not await navigate("w18") or not await navigate("c20") or not await enter_archive():
		await end_test()
		return
	check(level.resonance.collected.has("archive"), "A12 echo reached aboard the timber deck")
	if not await leave_archive() or not await navigate("e33") or not await navigate("e41"):
		await end_test()
		return
	if not await walk(Vector2(7296,2814)):
		await end_test()
		return
	await interact()
	check(level.open_doors.S2, "S2 is reached from the east via the archive descent")
	if not await walk(level.marker("c41")):
		await end_test()
		return
	nav_at = "c41"
	if not await descend_to_foundation() or not await navigate("w1_bank") or not await water_journey("W1"):
		await end_test()
		return
	if not await collect_echo("vault", 3966):
		await end_test()
		return
	if not await walk(Vector2(5312,3966)):
		await end_test()
		return
	check(level.resonance.collected.has("vault"), "A21 echo reached through W1")
	await interact()
	check(level.open_doors.S1, "W1 far latch creates a dry exit")
	nav_at = "vault"
	if not await walk(level.marker("vault")) or not await navigate("c60") or not await rise_to_lower_street():
		await end_test()
		return
	if not await lure_lion():
		await end_test()
		return
	while level.tide.is_surging(): await step(1)
	for i in 120:
		if standing() and absf(player.position.y - 3582.0) < 5.0: break
		await step(1)
	if not await walk(Vector2(6086, 3582)) or not await hop(Vector2(6158, 3582)) \
			or not await collect_echo("sealed_street", 3582) or not await walk(level.marker("e53")):
		await end_test()
		return
	nav_at = "e53"
	check(level.resonance.seal_open(), "A17's echo clears the physical altar seal")
	if await drop_to(Vector2(7968, 3902)) and await drop_to(Vector2(8024, 4222)) \
			and await descend_to_altar() and await navigate("boss"):
		check(level.drowned_count == 0, "A6 to A27 completed without resets or drowning")
		await capture("altar_unsealed")
	await end_test()


func enter_archive() -> bool:
	var tide: Node2D = level.tide
	if not await reach_ledge(Vector2(5910, 3582)): return false
	for i in 3600:
		if player.position.y < 450.0 and standing(): break
		await step(1)
	var high := player.position.y
	check(high < 450.0, "The A16 dock carries Lan to the crown aboard the board")
	if high >= 450.0: return false
	await capture("timber_deck_ride")
	# Sprint off the board, then air dash onto the archive landing.
	Input.action_press(&"ui_right")
	await step(2)
	Input.action_release(&"ui_right")
	await step(2)
	Input.action_press(&"ui_right")
	for i in 45:
		if player.position.x > tide.deck.end.x + 10.0 and not standing(): break
		await step(1)
	Input.action_press(&"instant_dash")
	await step(1)
	Input.action_release(&"instant_dash")
	for i in 145:
		if standing() and player.position.x > 6400.0 and absf(player.position.y - 1278.0) < 6.0: break
		await step(1)
	release()
	print("A12 WATER EXIT ", player.position, " high=", high)
	check(player.position.x > 6400.0 and absf(player.position.y - 1278.0) < 6.0, "Lan can disembark onto the upper archive bank")
	await capture("archive_water_exit")
	if player.position.x <= 6400.0 or absf(player.position.y - 1278.0) >= 6.0: return false
	if not await collect_echo("archive", 1278): return false
	if not await walk(level.marker("archive")): return false
	nav_at = "archive"
	return true


func collect_echo(id: String, floor_y: float) -> bool:
	var puzzle := (level as SunkenCavern).resonance
	var point: Vector2 = puzzle.echoes[id]
	if not await walk(Vector2(point.x, floor_y)): return false
	for i in ceili((puzzle.RETURN_INTERVAL + 2.0) * 60.0):
		if puzzle.collected.has(id): return true
		await step(1)
	check(false, "No collectible return wave reached " + id)
	return false


func leave_archive() -> bool:
	for at in [Vector2(6976, 1630), Vector2(6752, 1918), level.marker("archive_return")]:
		if not await reach_ledge(at): return false
	nav_at = "archive_return"
	return true


func reach_ledge(at: Vector2) -> bool:
	release()
	for i in 300:
		var dx := at.x - player.position.x
		if absf(dx) < 10 and absf(at.y - player.position.y) < 8 and standing():
			release()
			return true
		if dx > 7.0:
			Input.action_release(&"ui_left")
			Input.action_press(&"ui_right")
		elif dx < -7.0:
			Input.action_release(&"ui_right")
			Input.action_press(&"ui_left")
		else: release()
		await step(1)
	release()
	check(false, "Ledge %s not reached from %s" % [at, player.position])
	return false


func descend_to_foundation() -> bool:
	Input.action_press(&"ui_left")
	for i in 90:
		await step(1)
		if player.position.y > 2840.0: break
	release()
	if not await reach_ledge(Vector2(5740, 3582)): return false
	if not await walk(level.marker("c53")): return false
	nav_at = "c53"
	return true


func descend_to_altar() -> bool:
	if not await walk(Vector2(7616, 4222)): return false
	for at in [Vector2(7500, 4542), Vector2(7740, 4862), Vector2(7508, 5150), Vector2(7720, 5374)]:
		if not await reach_ledge(at): return false
	if not await walk(level.marker("ante")): return false
	nav_at = "ante"
	return true


func rise_to_lower_street() -> bool:
	var tide: Node2D = level.tide
	for i in 3600:
		if tide.surge_age() >= tide.W1_ARRIVAL and tide.surge_age() < tide.W1_ARRIVAL + 0.08: break
		await step(1)
	Input.action_press(&"ui_right")
	for i in 90:
		if player.position.x >= 5792.0: break
		await step(1)
	release()
	# At the lower exit, leave to the west before the water reaches the higher gallery.
	for i in 180:
		if absf(player.position.y - 3582.0) < 4.0: break
		await step(1)
	Input.action_press(&"ui_left")
	for i in 210:
		if player.position.x < tide.deck.position.x - 20.0: break
		await step(1)
	release()
	for i in 170:
		if standing() and absf(player.position.y - 3582.0) < 6.0: break
		await step(1)
	var at_street := absf(player.position.y - 3582.0) < 6.0
	check(at_street, "W1 dry exit returns by water to the A16 approach at %s" % player.position)
	return at_street


func lure_lion() -> bool:
	var lion: Node2D = level.stone_lion
	if not await walk(Vector2(5310,3582)): return false
	# Wait under the lower street's rock shoulder before going back into the shaft.
	while level.tide.surge_age() >= 0.0: await step(1)
	if not await walk(Vector2(5816,3582)): return false
	await capture("hammer_attack_prompt")
	key_event(KEY_J, true)
	await step(2)
	key_event(KEY_J, false)
	for i in 90:
		if is_instance_valid(lion._hammer_dialogue): break
		await step(1)
	check(is_instance_valid(lion._hammer_dialogue), "Real J contact with the hammer opens Lan's dialogue")
	if not is_instance_valid(lion._hammer_dialogue): return false
	await capture("hammer_dialogue")
	await tap_key(KEY_ENTER)
	if not await walk(Vector2(4974,3582)): return false
	await capture("lion_interaction_prompt")
	await interact()
	check(lion.state == lion.State.APPEARING, "Real E interaction wakes the dormant stone lion")
	if lion.state != lion.State.APPEARING: return false
	await capture("lion_awakens")
	# Leave the statue during its wake-up and lead the first charge from the hammer side.
	Input.action_press(&"ui_right")
	await step(2)
	Input.action_release(&"ui_right")
	await step(2)
	Input.action_press(&"ui_right")
	for i in 130:
		if player.position.x >= 5616.0: break
		await step(1)
	release()
	if not await walk(Vector2(5628,3582)): return false
	await capture("lion_before_charge")
	for i in 1050:
		if lion.broken: break
		var near_edge := CombatHitQuery.hurtbox_rect(player).position.x
		var charge_gap := maxf(0.0, near_edge - lion.position.x - lion.BODY.end.x)
		var time_to_contact: float = lion.WINDUP - lion._clock + charge_gap / lion.CHARGE_SPEED
		if lion.state == lion.State.WINDUP and lion._aims_at_lock and standing() and time_to_contact <= 0.65:
			Input.action_press(&"jump")
			await step(2)
			Input.action_release(&"jump")
			await step(20)
			Input.action_press(&"jump")
			await step(2)
			Input.action_release(&"jump")
		await step(1)
	check(lion.broken, "Luring a committed charge and clearing its path breaks A17")
	await capture("a17_open")
	return lion.broken


func tap_key(code: int) -> void:
	key_event(code, true)
	await step(1)
	key_event(code, false)
	await step(1)


func key_event(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

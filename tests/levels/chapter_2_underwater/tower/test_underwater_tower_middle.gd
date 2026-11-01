extends "test_underwater_tower_foundation.gd"
## Continues the real lower-loop journey into the middle loop without any warps.

func suite_name() -> String:
	return "UNDERWATER TOWER MIDDLE"

func journey() -> void:
	await super.journey()
	if failures > 0: return
	check(not level.middle_shortcut_is_open and not level.open_middle_shortcut(), "S2 starts locked and cannot be opened from the lower heart")
	if not await go(Vector2(1928, 2980), "walk"): return
	Input.action_press(&"ui_left")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 90:
		await step(1)
		if player.position.x < 1770 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x < 1800 and absf(player.position.y - 2980) < 6, "One normal jump crosses the 120 px S1 mouth to the west gallery")
	if failures > 0: return
	if not await go(Vector2(1340, 2980), "walk"): return
	Input.action_press(&"ui_right")
	await step(180)
	release()
	check(player.position.y > 2340.0 and not level.middle_shortcut_is_open, "Closed S2 hatch blocks ascending the actual return stair")
	check(not level.open_middle_shortcut(), "Below-hatch interaction cannot open S2")
	# Attempt an ordinary double jump at the closed hatch: its slab and adjacent
	# balcony form one solid floor, including the seam at the top of the stair.
	var highest_probe := player.position.y
	for i in 90:
		Input.action_press(&"ui_right")
		if i % 20 < 6: Input.action_press(&"jump")
		else: Input.action_release(&"jump")
		await step(1)
		highest_probe = minf(highest_probe, player.position.y)
	release()
	check(highest_probe > 2300.0 and not level.middle_shortcut_is_open, "Normal jumping cannot bypass the closed stair hatch (highest feet %.1f)" % highest_probe)
	# Recover through the already-open S1 if the attempted side jump drops into
	# its mouth. This is still the same continuous physics journey, never a warp.
	await step(45) # Let the attempted airborne turn/landing settle before choosing a bank.
	if player.position.x > 2300:
		if not await go(Vector2(2340, 2980), "walk"): return
		if not await jump_to(Vector2(2120, 2980), &"ui_left"): return
	elif player.position.x > 2180:
		if not await go(Vector2(2240, 3000), "breathe"): return
		if not await go(Vector2(2120, 2980), "exit"): return
	if not await go(Vector2(2000, 2980), "walk", 18.0): return
	if not await go(Vector2(1928, 2980), "walk"): return
	Input.action_press(&"ui_left")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 90:
		await step(1)
		if player.position.x < 1770 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	if not await go(Vector2(1340, 2980), "walk"): return
	var middle_min := 1.0
	var middle_swim := 0.0
	var old_max := maximum_continuous_swim
	var old_min := minimum_oxygen
	maximum_continuous_swim = 0.0
	minimum_oxygen = 1.0
	var route := [
		[Vector2(1140, 2980), "walk"],
		[Vector2(950, 2910), "walk"],
		[Vector2(780, 3060), "swim"],
		[Vector2(520, 3060), "swim"],
		[Vector2(520, 2380), "swim"],
		[Vector2(780, 2380), "swim"],
		[Vector2(780, 2240), "breathe"],
		[Vector2(1050, 2280), "exit"],
		[Vector2(1500, 2280), "walk"],
		[Vector2(1650, 2280), "walk"],
	]
	for i in route.size():
		if not await go(route[i][0], route[i][1]): return
		if i in [1, 5, 8, 10]: await capture("middle_%02d" % i)
	middle_min = minimum_oxygen
	minimum_oxygen = minf(old_min, middle_min)
	middle_swim = maximum_continuous_swim
	maximum_continuous_swim = maxf(old_max, middle_swim)
	check(level.current_room == &"T08" and not player.is_in_deep_water(), "West bypass reaches the actual dry upper bell gallery")
	check(level.oxygen.fraction() > 0.99 and level.drowned_count == 0, "Upper pool refills oxygen without drowning")
	check(middle_swim < 14.0, "Continuous middle-loop swim stays within the 14 s ceiling: %.2f s" % middle_swim)
	check(middle_min > 0.25, "Middle-loop oxygen retains a measured margin: %.3f" % middle_min)
	await step(20)
	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	await step(4)
	interact.pressed = false
	Input.parse_input_event(interact)
	check(level.middle_shortcut_is_open, "Real E at the upper latch opens S2")
	check(not player.ground_surfaces.has(level.MIDDLE_GATE_RECT), "Opened hatch releases its old standable surface")
	if not level.middle_shortcut_is_open: return
	if not await go(Vector2(1920, 2280), "walk"): return
	var before := frame_count
	if not await go(Vector2(1340, 2980), "walk", 15.0): return
	var return_seconds := (frame_count - before) / 60.0
	check(level.current_room == &"T04" and absf(player.position.y - 2980.0) < 1.0 and not player.is_in_deep_water(), "S2 returns to the lower heart on a real dry floor")
	check(return_seconds < 10.0, "Middle return is a short ordinary walk: %.2f s" % return_seconds)
	if not await go(Vector2(1920, 2280), "walk", 15.0): return
	check(absf(player.position.y - 2280.0) < 1.0 and level.current_room == &"T08", "S2 is also walkable upward without jumping or teleporting")
	for id in [&"T06", &"T07", &"T08"]:
		check(id in level.visited_rooms, "Physical route visits %s" % id)
	check(level.shortcut_is_open and level.middle_shortcut_is_open, "S1 and S2 retain independent open states")
	# The ordinary wet bypass remains reversible, independent of the new dry stair.
	if not await go(Vector2(1890, 2280), "walk"): return
	Input.action_press(&"ui_left")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 90:
		await step(1)
		if player.position.x < 1770 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x < 1780 and absf(player.position.y - 2280) < 2, "A normal jump crosses the open 100 px hatch back onto the upper gallery")
	if failures > 0: return
	for leg in [
		[Vector2(1050, 2280), "walk"],
		[Vector2(950, 2210), "walk"],
		[Vector2(780, 2380), "swim"],
		[Vector2(520, 2380), "swim"],
		[Vector2(520, 3060), "swim"],
		[Vector2(780, 3060), "swim"],
		[Vector2(780, 2940), "breathe"],
		[Vector2(1050, 2980), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	check(level.current_room == &"T06" and not player.is_in_deep_water(), "Wet bypass is also physically traversable back to the broken gallery")
	if not await go(Vector2(1920, 2280), "walk", 15.0): return
	check(level.drowned_count == 0, "Both loops and the reverse wet route finish without drowning")
	traversal_report["middle_max_swim_seconds"] = middle_swim
	traversal_report["middle_return_seconds"] = return_seconds
	traversal_report["middle_minimum_oxygen_fraction"] = middle_min
	traversal_report["minimum_oxygen_fraction"] = minimum_oxygen
	traversal_report["measured_max_unbroken_swim_seconds"] = maximum_continuous_swim
	await capture("middle_open")


func go(target: Vector2, mode: String, timeout := 24.0) -> bool:
	var reached := await super.go(target, mode, timeout)
	if not reached:
		for rect in level.wall_rects:
			if rect.grow(100).has_point(player.position): print("NEARBY WALL ", rect)
	return reached

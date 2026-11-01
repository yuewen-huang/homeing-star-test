extends "test_underwater_tower_middle.gd"
## Full entrance-to-observatory traversal, then S3 down/up and reverse water route.

func suite_name() -> String:
	return "UNDERWATER TOWER UPPER"

func journey() -> void:
	await super.journey()
	if failures > 0: return
	check(not level.upper_shortcut_is_open and not level.open_upper_shortcut(), "S3 starts locked and cannot be opened from the lower landing")
	if not await go(Vector2(2140, 2210), "walk"): return
	Input.action_press(&"ui_left")
	await step(300)
	release()
	check(player.position.y > 920.0 and not level.upper_shortcut_is_open, "Closed roof hatch blocks the real stone-spine stair")
	check(not level.open_upper_shortcut(), "S3 latch cannot be reached from beneath the closed hatch")
	if not await go(Vector2(2140, 2210), "walk", 20.0): return
	var first_max := maximum_continuous_swim
	var first_min := minimum_oxygen
	maximum_continuous_swim = 0.0
	minimum_oxygen = 1.0
	for leg in [
		[Vector2(2320, 2380), "swim"],
		[Vector2(2600, 2380), "swim"],
		[Vector2(2600, 1760), "swim"],
		[Vector2(2140, 1760), "swim"],
		[Vector2(2140, 1580), "breathe"],
		[Vector2(2320, 1550), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	var riser_max := maximum_continuous_swim
	check(level.current_room == &"T10" and absf(player.position.y - 1550) < 2 and not player.is_in_deep_water(), "Upper flooded riser reaches the real crown breathing platform")
	await capture("upper_crown")
	for leg in [
		[Vector2(2140, 1700), "swim"],
		[Vector2(1940, 1700), "swim"],
		[Vector2(1940, 1340), "breathe"],
		[Vector2(1960, 1340), "breathe"],
		[Vector2(2220, 1380), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	check(level.current_room == &"T11" and not player.is_in_deep_water(), "Submerged cross-passage reaches the dry scroll library")
	await capture("upper_library")
	if not await go(Vector2(2448, 860), "walk", 20.0): return
	Input.action_press(&"ui_right")
	await step(30)
	release()
	check(player.position.x > 2440 and absf(player.position.y - 860) < 2, "Library stair arrives on the actual eastern roof landing")
	await step(45) # finish the ordinary landing roll against the wall before turning
	Input.action_press(&"ui_left")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 90:
		await step(1)
		if player.position.x < 2320 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x < 2340 and absf(player.position.y - 860) < 2, "Normal jump crosses the eastern stair mouth into the observatory")
	if failures > 0: return
	if not await go(Vector2(1360, 860), "walk"): return
	check(level.current_room == &"T12" and absf(player.position.y - 860) < 2, "Existing walking climbs the intact library stair to the observatory")
	var upper_max := maximum_continuous_swim
	var upper_min := minimum_oxygen
	maximum_continuous_swim = maxf(first_max, upper_max)
	minimum_oxygen = minf(first_min, upper_min)
	check(upper_max < 14.0, "Upper swim segments retain a breathing break: %.2f s max" % upper_max)
	check(upper_min > 0.25, "Upper route retains oxygen: %.3f minimum" % upper_min)
	await step(20)
	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	await step(4)
	interact.pressed = false
	Input.parse_input_event(interact)
	check(level.upper_shortcut_is_open, "Real E on the observatory side opens S3")
	check(not player.ground_surfaces.has(level.UPPER_GATE_RECT), "S3 opening removes its old floor support")
	if not level.upper_shortcut_is_open: return
	if not await go(Vector2(1220, 860), "walk"): return
	Input.action_press(&"ui_left")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 90:
		await step(1)
		if player.position.x < 1070 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x < 1080 and absf(player.position.y - 860) < 2, "One normal jump crosses the 120 px roof hatch")
	var before := frame_count
	if not await go(Vector2(2160, 2210), "walk", 20.0): return
	var return_seconds := (frame_count - before) / 60.0
	check(not player.is_in_deep_water() and level.current_room == &"T09", "S3 returns to the eastern landing without entering a water passage")
	check(return_seconds < 12.0, "S3 is a short continuous dry return: %.2f s" % return_seconds)
	if not await go(Vector2(1040, 860), "walk", 20.0): return
	check(absf(player.position.y - 860) < 2, "Opened S3 is also walkable upward from the eastern turning landing")
	for id in [&"T09", &"T10", &"T11", &"T12"]:
		check(id in level.visited_rooms, "Physical route visits %s" % id)
	check(level.shortcut_is_open and level.middle_shortcut_is_open and level.upper_shortcut_is_open, "All three shortcuts retain independent open states")
	# Reverse the normal route as well: no newly opened shortcut is required to
	# retreat from the library through either breathing pool to the eastern landing.
	release()
	await step(20)
	Input.action_press(&"ui_right")
	for i in 40:
		if player.position.x >= 1060: break
		await step(1)
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 100:
		await step(1)
		if player.position.x > 1220 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x > 1200 and absf(player.position.y - 860) < 2, "The open roof hatch is also crossed eastward with one normal jump")
	for leg in [
		[Vector2(2320, 860), "walk"],
	]:
		if not await go(leg[0], leg[1]): return
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 100:
		await step(1)
		if player.position.x > 2440 and player.air_state == LanPlayer.AirState.GROUNDED: break
	release()
	check(player.position.x > 2440 and absf(player.position.y - 860) < 2, "Normal jump returns to the east stair for the reverse route")
	for leg in [
		[Vector2(1940, 1700), "swim"],
		[Vector2(2140, 1700), "swim"],
		[Vector2(2140, 1580), "breathe"],
		[Vector2(2320, 1550), "exit"],
		[Vector2(2140, 1760), "swim"],
		[Vector2(2600, 1760), "swim"],
		[Vector2(2600, 2380), "swim"],
		[Vector2(2320, 2380), "swim"],
		[Vector2(2320, 2240), "breathe"],
		[Vector2(2260, 2240), "breathe"],
		[Vector2(2060, 2280), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	check(not player.is_in_deep_water() and level.current_room == &"T09", "Both upper water segments are physically traversable in reverse")
	check(maximum_continuous_swim < 14.0 and minimum_oxygen > 0.20, "Forward and reverse upper paths both retain the oxygen budget")
	check(level.drowned_count == 0, "Complete twelve-space route has no drowning")
	traversal_report["upper_riser_max_swim_seconds"] = riser_max
	traversal_report["upper_max_swim_seconds"] = upper_max
	traversal_report["upper_minimum_oxygen_fraction"] = upper_min
	traversal_report["upper_return_seconds"] = return_seconds
	traversal_report["minimum_oxygen_fraction"] = minimum_oxygen
	traversal_report["measured_max_unbroken_swim_seconds"] = maximum_continuous_swim
	await capture("upper_open")

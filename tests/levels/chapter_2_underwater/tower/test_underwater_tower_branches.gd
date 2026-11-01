extends "test_underwater_tower_foundation.gd"
## First exploration with all return hatches closed. No position resets in journey.

func suite_name() -> String:
	return "UNDERWATER TOWER FIRST-EXPLORATION BRANCHES"


func journey() -> void:
	for leg in [
		[Vector2(830,3550), "walk"], [Vector2(640,3740), "jump_into_water"],
		[Vector2(640,4200), "swim"], [Vector2(1080,4200), "swim"],
		[Vector2(1080,4040), "breathe"], [Vector2(1220,4010), "exit"],
		[Vector2(1080,4200), "swim"], [Vector2(2140,4200), "swim"],
		[Vector2(2140,4000), "breathe"], [Vector2(2330,3970), "exit"],
		[Vector2(2140,4200), "swim"], [Vector2(2600,4200), "swim"],
		[Vector2(2600,3600), "swim"], [Vector2(2460,3625), "swim"],
		[Vector2(2300,3625), "swim"], [Vector2(2300,3560), "breathe"],
		[Vector2(2390,3530), "exit"], [Vector2(2300,3625), "swim"],
		[Vector2(2460,3625), "swim"], [Vector2(2600,3600), "swim"],
		[Vector2(2600,3300), "swim"], [Vector2(2380,3300), "swim"],
		[Vector2(2240,3300), "swim"], [Vector2(2240,3000), "breathe"],
		[Vector2(2120,2980), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	check(level.current_room == &"T04" and not player.is_in_deep_water(), "E12 reaches the heart from the east well")
	check(&"T05" not in level.visited_rooms, "First exploration can bypass the old archive")
	check(not level.shortcut_is_open and not level.middle_shortcut_is_open and not level.upper_shortcut_is_open, "E12 needs no open shortcut")
	await capture("maintenance_landing")
	check(maximum_continuous_swim < 14, "Forward E12 swim segments stay under 14 seconds")
	var forward_max := maximum_continuous_swim
	maximum_continuous_swim = 0.0
	for leg in [
		[Vector2(2240,3300), "jump_into_water"], [Vector2(2380,3300), "swim"],
		[Vector2(2600,3300), "swim"], [Vector2(2600,2940), "breathe"],
		[Vector2(2600,3300), "swim"], [Vector2(2380,3300), "swim"],
		[Vector2(2240,3300), "swim"], [Vector2(2240,3000), "breathe"],
		[Vector2(2120,2980), "exit"],
	]:
		if not await go(leg[0], leg[1]): return
	check(level.drowned_count == 0, "Maintenance water route is traversable in both directions")
	check(maximum_continuous_swim < 14, "Maintenance reverse swim has an oxygen margin")
	var reverse_max := maximum_continuous_swim
	maximum_continuous_swim = maxf(forward_max, reverse_max)
	if not await go(Vector2(1928,2980), "walk"): return
	if not await jump_to(Vector2(1740,2980), &"ui_left"): return
	for leg in [
		[Vector2(1140,2980), "walk"], [Vector2(950,2910), "walk"],
		[Vector2(780,3060), "swim"], [Vector2(520,3060), "swim"],
		[Vector2(520,2380), "swim"], [Vector2(780,2380), "swim"],
		[Vector2(780,2240), "breathe"], [Vector2(1050,2280), "exit"],
		[Vector2(1650,2280), "walk"], [Vector2(1920,2280), "walk"],
		[Vector2(2140,2210), "walk"], [Vector2(1240,1100), "walk"],
	]:
		if not await go(leg[0], leg[1]): return
	if not await jump_to(Vector2(1420,1100), &"ui_right"): return
	if not await go(Vector2(2260,1100), "walk"): return
	check(not player.is_in_deep_water() and absf(player.position.y - 1100) < 2, "E13 is a real dry mezzanine floor")
	check(level.current_room == &"T11", "Book gallery connects the dry spine to the library")
	await capture("book_gallery")
	if not await jump_to(Vector2(2448,860), &"ui_right", 240): return
	check(not level.upper_shortcut_is_open, "Library stair can reach the roof while S3 is still closed")
	await step(45)
	if not await go(Vector2(2340,1100), "walk"): return
	if not await jump_to(Vector2(2230,1100), &"ui_left"): return
	if not await go(Vector2(1360,1100), "walk"): return
	if not await jump_to(Vector2(1250,1118), &"ui_left"): return
	if not await go(Vector2(2140,2210), "walk"): return
	check(level.current_room == &"T09" and not player.is_in_deep_water(), "E13 returns to the middle landing entirely dry")
	check(not level.shortcut_is_open and not level.middle_shortcut_is_open and not level.upper_shortcut_is_open, "Both first-exploration branches preserve all three closed hatches")
	check(level.drowned_count == 0, "Complete alternate-route journey has no drowning")
	traversal_report = {"checks":checks, "failures":failures, "maintenance_reverse_max_swim_seconds":reverse_max, "minimum_oxygen_fraction":minimum_oxygen, "measured_max_unbroken_swim_seconds":maximum_continuous_swim, "visited":level.visited_rooms}

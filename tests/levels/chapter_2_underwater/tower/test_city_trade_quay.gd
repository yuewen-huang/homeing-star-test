extends "test_underwater_tower_foundation.gd"

func run() -> void:
	use_memory_progress()
	level = (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	player.reset_after_map_fall(Vector2(3500, 760))
	await step(25)
	for leg in [
		[Vector2(3650, 760), "walk"], [Vector2(3860, 900), "jump_into_water"],
		[Vector2(4300, 900), "swim"], [Vector2(4780, 900), "swim"],
		[Vector2(5320, 900), "swim"],
	]:
		if not await go(leg[0], leg[1]): break
	check(player.position.x > 5280, "Real swimming reaches the open quay beyond the previous map edge")
	check(not level.merchant_hall.occupied and level.merchant_hall.facade_alpha > 0.99, "Warehouse closes visually while leaving for the open quay")
	check(level.camera.position.x > 4500, "Camera follows continuously into the new dock area")
	Input.action_press(&"ui_down")
	for i in 120:
		await step(1)
		if absf(player.position.y - 980) < 2 and player.air_state != LanPlayer.AirState.SWIMMING: break
	release()
	await step(12)
	check(absf(player.position.y - 980) < 2, "Character lands on the same level stone shore without invisible ledges")
	var held_oxygen: float = level.oxygen.fraction()
	await step(60)
	check(level.oxygen.mode == UnderwaterOxygen.Mode.HOLDING and absf(level.oxygen.fraction() - held_oxygen) < 0.01, "Existing underwater-ground movement holds oxygen without refilling")
	if failures == 0:
		check(await walk_shore_to(4140), "Flat shore is walkable back past the dock scenery")
		check(absf(level.oxygen.fraction() - held_oxygen) < 0.02, "Walking the submerged shore keeps the existing oxygen behavior")
		for leg in [[Vector2(3870, 900), "swim"], [Vector2(3850, 780), "breathe"], [Vector2(3500, 760), "exit"]]:
			if not await go(leg[0], leg[1]): break
	check(level.drowned_count == 0 and not player.is_in_deep_water(), "Dock journey returns to the original warehouse air bank without drowning")
	check(minimum_oxygen > 0.05, "Route retains an oxygen margin: %.2f" % minimum_oxygen)
	release()
	stop_test_audio()
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	stop_test_audio()
	await wait_frames(4)
	finish("CITY TRADE QUAY")


func walk_shore_to(x: float) -> bool:
	for i in 1500:
		if absf(player.position.x - x) < 24:
			release()
			return absf(player.position.y - 980) < 3
		Input.action_press(&"ui_left")
		await step(1)
		if absf(player.position.y - 980) > 5:
			release()
			return false
	release()
	return false

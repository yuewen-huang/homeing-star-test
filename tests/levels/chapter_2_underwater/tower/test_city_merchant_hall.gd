extends "test_underwater_tower_foundation.gd"

func run() -> void:
	use_memory_progress()
	level = (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	player.reset_after_map_fall(Vector2(1100, 770))
	await step(25)
	for leg in [
		[Vector2(1320, 900), "jump_into_water"], [Vector2(1760, 900), "swim"],
		[Vector2(2200, 900), "swim"], [Vector2(2580, 900), "swim"],
		[Vector2(2820, 900), "swim"], [Vector2(2880, 780), "breathe"],
		[Vector2(3200, 760), "exit"], [Vector2(3380, 760), "walk"],
	]:
		if not await go(leg[0], leg[1]): break
	await step(24)
	check(not player.is_in_deep_water() and absf(player.position.y - 760) < 3, "Normal swimming exit reaches the warehouse's dry stone floor")
	check(level.oxygen.fraction() > 0.99, "Warehouse air restores the existing oxygen bar")
	check(level.merchant_hall.occupied and level.merchant_hall.facade_alpha < 0.07, "Warehouse facade reveals independently of the gate")
	check(not level.gate_room.occupied and level.gate_room.facade_alpha > 0.99, "Distant city gate remains closed visually")
	if failures == 0:
		for leg in [
			[Vector2(3650, 760), "walk"], [Vector2(3860, 900), "jump_into_water"],
			[Vector2(4120, 900), "swim"], [Vector2(4300, 900), "swim"],
			[Vector2(4100, 900), "swim"], [Vector2(3870, 900), "swim"],
			[Vector2(3850, 780), "breathe"], [Vector2(3500, 760), "exit"],
		]:
			if not await go(leg[0], leg[1]): break
	check(level.drowned_count == 0, "Both warehouse entrances work without drowning")
	check(maximum_continuous_swim < 19.0, "Measured longest swim fits the unchanged oxygen bar: %.2f s" % maximum_continuous_swim)
	if failures == 0:
		# Separate roof check, after measuring the continuous room-to-room journey.
		player.reset_after_map_fall(Vector2(3300, 200))
		level.oxygen.fill()
		await step(24)
		check(player.is_in_deep_water() and not level.merchant_hall.occupied, "Ocean above the warehouse stays swimmable without revealing the room")
		Input.action_press(&"ui_down")
		await step(110)
		release()
		check(player.position.y < 370 and not level.merchant_hall.occupied, "Roof collision stops downward swimming on the roof silhouette")
	var labels := 0
	for label in level.find_children("*", "Label", true, false):
		if not player.is_ancestor_of(label): labels += 1
	check(labels == 0, "Merchant hall adds no helper labels")
	release()
	stop_test_audio()
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	stop_test_audio()
	await wait_frames(4)
	finish("CITY MERCHANT HALL")

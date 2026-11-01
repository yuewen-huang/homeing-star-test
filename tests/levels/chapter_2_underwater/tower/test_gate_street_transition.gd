extends "test_underwater_tower_foundation.gd"
## Swim beyond the former map boundary and return through the same continuous road.

func run() -> void:
	use_memory_progress()
	level = (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	# Establish the approved gate bank as this journey's initial air point only.
	player.reset_after_map_fall(Vector2(1100, 770))
	await step(25)
	check(not player.is_in_deep_water(), "Transition journey starts at the existing gate air bank")
	var seam_y := 980.0
	for piece in level._terrain.get_children():
		if piece.position.x <= 1920 and piece.position.x + piece.size.x >= 2400:
			seam_y = piece.position.y
	check(seam_y == 980 and level.ROAD.end.x >= 2400, "One flat solid spans both sides of the old map edge")
	for leg in [
		[Vector2(1320, 900), "jump_into_water"],
		[Vector2(1760, 900), "swim"],
		[Vector2(1980, 900), "swim"],
		[Vector2(2200, 900), "swim"],
		[Vector2(2430, 900), "swim"],
	]:
		if not await go(leg[0], leg[1]): break
	check(player.position.x > 2390, "Real input reaches the ruined merchant-gallery entrance")
	check(not level.gate_room.occupied and level.gate_room.facade_alpha > 0.99, "Gate exterior restores while swimming away into the street")
	check(level.camera.position.x > 1400, "Camera follows continuously beyond the former right limit")
	if failures == 0:
		for leg in [
			[Vector2(2200, 900), "swim"], [Vector2(1760, 900), "swim"],
			[Vector2(1480, 900), "swim"], [Vector2(1360, 900), "swim"],
			[Vector2(1280, 800), "breathe"], [Vector2(1100, 770), "exit"],
		]:
			if not await go(leg[0], leg[1]): break
	check(level.drowned_count == 0, "Transition round trip needs no new oxygen refill or drowning reset")
	check(maximum_continuous_swim < 19.0, "Measured uninterrupted round trip fits the existing bar: %.2f s" % maximum_continuous_swim)
	check(not player.is_in_deep_water() and level.oxygen.fraction() > 0.99, "Return uses the existing gate air bank and normal jump")
	var labels := 0
	for label in level.find_children("*", "Label", true, false):
		if not player.is_ancestor_of(label): labels += 1
	check(labels == 0, "Transition adds no helper labels")
	release()
	stop_test_audio()
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	stop_test_audio()
	await wait_frames(4)
	finish("GATE STREET TRANSITION")

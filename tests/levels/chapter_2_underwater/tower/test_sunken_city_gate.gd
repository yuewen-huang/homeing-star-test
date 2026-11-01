extends "test_underwater_tower_foundation.gd"
## Gate theme only: real-input travel in both directions, including normal water jumps.

func run() -> void:
	use_memory_progress()
	output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sunken_city_gate_20261031")
	level = (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	await step(30)
	check(player.is_in_deep_water(),"Approach starts inside the submerged outer city")
	check(not level.gate_room.occupied and level.gate_room.facade_alpha > 0.99,"Gate exterior stays opaque on approach")
	for leg in [
		[Vector2(480,900),"swim"], [Vector2(760,900),"swim"],
		[Vector2(840,800),"breathe"], [Vector2(1040,770),"exit"],
		[Vector2(1100,770),"walk"],
	]:
		if not await go(leg[0],leg[1]): break
		if leg[0] == Vector2(760,900):
			await step(22)
			check(level.gate_room.occupied and level.gate_room.facade_alpha < 0.07,"Swimming through the gate reveals the room")
	check(not player.is_in_deep_water() and absf(player.position.y-770)<2,"Normal jump lands on the gatehouse's broad dry bank")
	check(level.oxygen.fraction()>0.99,"Gatehouse air restores the existing oxygen bar")
	if failures==0:
		for leg in [
			[Vector2(1320,900),"jump_into_water"], [Vector2(1480,900),"swim"],
			[Vector2(1580,900),"swim"], [Vector2(1760,850),"swim"],
			[Vector2(1480,900),"swim"], [Vector2(1360,900),"swim"],
			[Vector2(1280,800),"breathe"], [Vector2(1100,770),"exit"],
			[Vector2(840,900),"jump_into_water"], [Vector2(480,900),"swim"],
			[Vector2(200,850),"swim"],
		]:
			if not await go(leg[0],leg[1]): break
	check(failures==0 and player.position.x<250,"Both low-water doorways and the bank are traversable in reverse")
	await step(22)
	check(not level.gate_room.occupied and level.gate_room.facade_alpha > 0.99,"Exterior restores after the return exit")
	check(level.drowned_count==0,"Gate journey has no drowning")
	check(maximum_continuous_swim<14,"Longest uninterrupted swim retains room to explore: %.2f seconds" % maximum_continuous_swim)
	var helper_labels := 0
	for label in level.find_children("*","Label",true,false):
		if not player.is_ancestor_of(label): helper_labels+=1
	check(helper_labels==0,"No new helper labels")
	release()
	stop_test_audio()
	await wait_frames(3)
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	stop_test_audio()
	await wait_frames(4)
	finish("SUNKEN CITY GATE")

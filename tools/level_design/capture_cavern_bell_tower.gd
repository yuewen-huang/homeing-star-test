extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Real-input bell-tower loop and ladder/chamber art review, without warps.


func run() -> void:
	use_memory_progress()
	output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_bell_tower_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	check(is_instance_valid(level.entrance_art.get_node_or_null("WestBellTower/BellPavilion")),"The west tower uses the new Chinese bell-pavilion artwork")
	await capture("01_entrance_preserved")
	for goal in ["w36","w28","bell28"]:
		if not await navigate(goal):
			await end_bell_test()
			return
	check(standing() and not player.is_in_deep_water(),"The existing lower tower entrance remains a dry landing")
	await capture("02_lower_gallery")
	if not await navigate("route_26_3"):
		await end_bell_test()
		return
	await capture("03_broken_stairs")
	if not await navigate("bell18"):
		await end_bell_test()
		return
	check(standing(),"The authored timber stairs and ordinary jumps reach the upper entrance")
	await capture("04_upper_gallery")
	for goal in ["route_27_1","route_27_3","bell_top"]:
		if not await navigate(goal):
			await end_bell_test()
			return
		await capture("05_first_gallery" if goal=="route_27_1" else ("06_bell_approach" if goal=="route_27_3" else "07_bell_chamber"))
	check(standing() and absf(player.position.y-766)<4,"The original three short ladders reach the real bell-chamber landing")
	await jump_in_place("bell chamber")
	if not await navigate("bell18"):
		await end_bell_test()
		return
	await capture("08_return_gallery")
	if not await navigate("w18"):
		await end_bell_test()
		return
	check(standing() and not player.is_in_deep_water(),"The other doorway reconnects to the upper west street well")
	await capture("09_upper_well_exit")
	for goal in ["w28","w36","entry"]:
		if not await navigate(goal):
			await end_bell_test()
			return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The tower circuit preserves dry movement and oxygen")
	check(player.position.distance_to(level.start)<16,"Continuous tower traversal returns to the original entrance without position resets")
	await end_bell_test()


func end_bell_test() -> void:
	release()
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":true,"position_resets":0,"tour":tour,
		"final_position":[player.position.x,player.position.y],"drowned":level.drowned_count}
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	report.checks=checks
	report.failures=failures
	var file:=FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	finish("CAVERN BELL TOWER ART")

extends "capture_cavern_east_crypt.gd"
## Fixed poses are explicit resets; the ordinary tour uses only real input.

func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(640,360)
		root.size=Vector2i(640,360)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	check(level.entrance_art.get_node_or_null("FinalCityLandmarks/TwinFishAltar")!=null,"New grounded paired-fish altar is present")
	check(level.layout.ladders.size()==10 and level.layout.water_itineraries.size()==2,"Final art preserves route and water geometry")
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_altar_centre",Vector2(8832,5374)],["02_altar_approach",Vector2(8128,5374)],
			["03_altar_east",Vector2(9408,5374)],["04_vault",Vector2(5184,3966)],
			["05_foundation_bank",Vector2(3344,3966)],["06_culvert",Vector2(4224,4296)],
			["07_upper_bridge",Vector2(4000,1470)],["08_middle_arch",Vector2(6672,2814)],
			["09_entrance",level.start],["10_forecourt",Vector2(7712,5374)]]:
			player.reset_after_map_fall(sample[1])
			await step(18)
			await capture(sample[0])
		await finish_final(false)
		return
	for goal in ["w36","w28","w18","c20","c12","c33","archive_return","e33","e41"]:
		if not await navigate(goal):
			await finish_final(true)
			return
	# Release S2 from its authored far side and cross both ways.
	if not await walk(Vector2(7296,2814)):
		await finish_final(true)
		return
	await interact()
	check(level.open_doors.S2,"S2 textured gate still opens from the east latch")
	await walk(Vector2(7088,2814))
	await walk(level.marker("e41"))
	nav_at="e41"
	for goal in ["e53","e64","route_23_0","ante","boss"]:
		if not await navigate(goal):
			await finish_final(true)
			return
	await capture("tour_altar")
	await jump_in_place("dry altar arena")
	check(await walk(Vector2(9472,5374)) and await walk(level.marker("boss")),"Dry arena remains open across its width")
	for goal in ["ante","c75","c60","c53","w53","w1_bank"]:
		if not await navigate(goal):
			await finish_final(true)
			return
	if not await water_journey("W1"):
		await finish_final(true)
		return
	nav_at="vault"
	await capture("tour_vault_closed")
	if not await walk(Vector2(5312,3966)):
		await finish_final(true)
		return
	await interact()
	check(level.open_doors.S1,"S1 textured gate still opens from inside the dry vault")
	await capture("tour_vault_open")
	await walk(level.marker("vault"))
	for goal in ["c60","c53","c37","entry"]:
		if not await navigate(goal):
			await finish_final(true)
			return
	check(level.drowned_count==0 and min_oxygen>0.15,"Foundation swim completes without drowning with over 15% oxygen remaining")
	check(player.position.distance_to(level.start)<16,"Final-art real-input tour returns to the entrance without resets")
	await finish_final(true)

func finish_final(continuous: bool) -> void:
	release()
	var report={"checks":checks,"failures":failures,"continuous_real_input":continuous,
		"position_resets":0 if continuous else 10,"game_seconds":frames/60.0,"tour":tour,
		"longest_swim":longest_swim,"min_oxygen":min_oxygen,"drowned":level.drowned_count,
		"altar_patch":{"air":level.entrance_art._altar_patch.air_count,"contours":level.entrance_art._altar_patch.contour_count,"roads":level.entrance_art._altar_patch.road_count}}
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	report.checks=checks
	report.failures=failures
	var file:=FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	finish("CAVERN FINAL ENVIRONMENT")

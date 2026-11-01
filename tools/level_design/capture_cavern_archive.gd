extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Continuous archive entry, broken-floor descent and lower-gallery return.


func run() -> void:
	use_memory_progress()
	output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_archive_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	check(is_instance_valid(level.entrance_art.get_node_or_null("UpperArchive/ArchiveWritingTable")),"The upper archive uses the new rear lattice and writing-table art")
	await capture("01_entrance_preserved")
	for goal in ["w36","w28","w18","c20","c12"]:
		if not await navigate(goal):
			await end_archive_test()
			return
	check(standing() and not player.is_in_deep_water(),"The existing upper approach reaches the archive's west doorway")
	await capture("02_west_patch_join")
	if not await walk(Vector2(6464,1278)):
		await end_archive_test()
		return
	check(standing() and absf(player.position.y-1278)<4,"The writing table stands behind the original readable floor")
	await capture("03_archive_reading_room")
	await jump_in_place("archive reading room")
	if not await navigate("archive"):
		await end_archive_test()
		return
	check(standing(),"The surviving timber floor still reaches the broken east bay")
	await capture("04_broken_east_bay")
	if not await navigate("route_28_0"):
		await end_archive_test()
		return
	check(standing() and absf(player.position.y-1630)<4,"The original floor break leads to the real intermediate beam")
	await capture("05_intermediate_beam")
	if not await navigate("archive_return"):
		await end_archive_test()
		return
	check(standing() and absf(player.position.y-2302)<4,"The separate descent returns to the lower east gallery")
	await capture("06_lower_gallery_return")
	if not await navigate("c33"):
		await end_archive_test()
		return
	check(standing() and not player.is_in_deep_water(),"The archive loop reconnects to the central shaft at a different height")
	await capture("07_lower_patch_join")
	for goal in ["c37","entry"]:
		if not await navigate(goal):
			await end_archive_test()
			return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The archive circuit preserves dry movement and oxygen")
	check(player.position.distance_to(level.start)<16,"The continuous archive tour returns to the original entrance without warps")
	await end_archive_test()


func end_archive_test() -> void:
	release()
	var patch=level.entrance_art._archive_patch
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":true,"position_resets":0,"tour":tour,
		"final_position":[player.position.x,player.position.y],"drowned":level.drowned_count,
		"archive_patch":{"air":patch.air_count,"contours":patch.contour_count,"roads":patch.road_count}}
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
	finish("CAVERN UPPER ARCHIVE ART")

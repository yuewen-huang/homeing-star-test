extends "capture_cavern_central_well.gd"
## Dry western crypt circuit; fixed art samples are separately reported.


func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(640,360)
		root.size=Vector2i(640,360)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_west_crypt_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_dry_turn",Vector2(2560,3582)],["02_dry_shaft",Vector2(2560,4286)],
			["03_west_bend",Vector2(3072,4990)],["04_crypt_west",Vector2(4480,4990)],
			["05_crypt_east",Vector2(5120,4990)],["06_well_join",Vector2(5824,4990)]]:
			player.reset_after_map_fall(sample[1])
			await step(18)
			await capture(sample[0])
		await end_crypt_test(false)
		return
	check(is_instance_valid(level.entrance_art.get_node_or_null("WestCrypt/LowGalleryWall")),"The low west crypt has its own grounded gallery art")
	check(is_instance_valid(level.entrance_art.get_node_or_null("WestCrypt/CollapsedVaultShoulder")),"The dry return has one broken stone vault shoulder")
	check(level.layout.ladders.size()==10,"Crypt art adds no new ladders")
	var crypt_visits:=0
	for goal in ["w36","w28","w18","c20","c12","c33","c37","c41","c53","w53","dry_turn","dry_base","c75","dry_base","c75","c60","c53","c37","entry"]:
		if not await navigate(goal):
			await end_crypt_test(true)
			return
		if goal in ["dry_turn","dry_base","c75"]:
			check(standing() and not player.is_in_deep_water(),"The existing dry crypt route remains reachable: "+goal)
			await capture("route_"+goal)
		if goal=="dry_base":
			if not await walk(Vector2(3072,4990)):
				await end_crypt_test(true)
				return
			await capture("west_vault_foot")
			if crypt_visits==0: await jump_in_place("west return")
			if not await walk(level.marker("dry_base")):
				await end_crypt_test(true)
				return
		if goal=="c75":
			crypt_visits+=1
			if not await walk(Vector2(4704,4990)):
				await end_crypt_test(true)
				return
			await capture("low_crypt_gallery")
			if crypt_visits==1: await jump_in_place("low crypt gallery")
			if not await walk(level.marker("c75")):
				await end_crypt_test(true)
				return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The western crypt loop stays dry without drowning")
	check(player.position.distance_to(level.start)<16,"The continuous dry crypt circuit returns to the original entry")
	await end_crypt_test(true)


func end_crypt_test(continuous: bool) -> void:
	release()
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":continuous,"fixed_camera_samples":not continuous,
		"position_resets":0 if continuous else 6,"tour":tour,
		"final_position":[player.position.x,player.position.y],"drowned":level.drowned_count}
	if "_crypt_patch" in level.entrance_art:
		var patch=level.entrance_art._crypt_patch
		report.crypt_patch={"air":patch.air_count,"contours":patch.contour_count,"roads":patch.road_count,"timbers":patch.timber_segments.size()}
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
	finish("CAVERN WEST CRYPT ART")

extends "capture_cavern_central_well.gd"
## Real-input east-shaft descent and two-way lower-crypt stair circuit.


func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(640,360)
		root.size=Vector2i(640,360)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_east_crypt_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_low_gallery",Vector2(6528,4990)],["02_upper_turn",Vector2(7616,4222)],
			["03_mid_stair",Vector2(7648,4862)],["04_lower_steps",Vector2(7456,5246)],
			["05_forecourt",Vector2(7712,5374)],["06_well_join",Vector2(6272,4990)]]:
			player.reset_after_map_fall(sample[1])
			await step(18)
			await capture(sample[0])
		await end_east_crypt_test(false)
		return
	check(is_instance_valid(level.entrance_art.get_node_or_null("EastCrypt/StoneGallery")),"The east crypt has a grounded stone gallery")
	check(is_instance_valid(level.entrance_art.get_node_or_null("EastCrypt/ForecourtBalustrade")),"The lower forecourt has a grounded rear balustrade")
	check(level.layout.ladders.size()==10,"Painting adds no new ladders")
	var low_visits:=0
	for goal in ["w36","w28","w18","c20","c12","c33","archive_return","e33","e41","e53","e64",
		"route_23_0","ante","c75","ante","c75","c60","c53","c37","entry"]:
		if not await navigate(goal):
			await end_east_crypt_test(true)
			return
		if goal in ["e64","route_23_0","ante","c75"]:
			check(standing() and not player.is_in_deep_water(),"Existing dry east-crypt landing remains reachable: "+goal)
			await capture("route_"+goal)
		if goal=="c75":
			low_visits+=1
			if not await walk(Vector2(6528,4990)):
				await end_east_crypt_test(true)
				return
			await capture("low_gallery")
			if low_visits==1: await jump_in_place("east stone gallery")
			if not await walk(level.marker("c75")):
				await end_east_crypt_test(true)
				return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The complete east crypt circuit remains dry")
	check(player.position.distance_to(level.start)<16,"The continuous circuit returns to the original entrance")
	await end_east_crypt_test(true)


## Keep a deliberate direction held through these narrow lips, then brake in
## the open drop. Re-aiming immediately after losing support can recontact the
## opposite stone edge and cycle the landing clip. Inputs only, no actor writes.
func descend(target: Vector2,chute_x: float=NAN) -> bool:
	if absf(player.position.y-3582)<5 and absf(target.y-4222)<5:
		if not await drop_to(Vector2(7968,3902)): return false
		if not await drop_to(Vector2(8024,4222)): return false
		return await walk(target)
	if absf(player.position.y-4222)<5 and absf(target.y-5374)<5:
		for landing in [Vector2(7508,4542),Vector2(7680,4862),Vector2(7548,5150),Vector2(7680,5374)]:
			if not await drop_to(landing): return false
		return await walk(target)
	return await super.descend(target,chute_x)


func end_east_crypt_test(continuous: bool) -> void:
	release()
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":continuous,"fixed_camera_samples":not continuous,
		"position_resets":0 if continuous else 6,"tour":tour,"drowned":level.drowned_count,
		"final_position":[player.position.x,player.position.y]}
	if "_east_crypt_patch" in level.entrance_art:
		var patch=level.entrance_art._east_crypt_patch
		report.east_crypt_patch={"air":patch.air_count,"contours":patch.contour_count,"roads":patch.road_count,"timbers":patch.timber_segments.size()}
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
	finish("CAVERN EAST CRYPT ART")

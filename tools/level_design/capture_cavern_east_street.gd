extends "capture_cavern_central_well.gd"
## East gallery and ruined-street art: fixed views are separate from the
## continuous real-input circuit. Reuses the local ordinary-input driver.


func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(640,360)
		root.size=Vector2i(640,360)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_east_street_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_upper_gallery",Vector2(7552,2302)],["02_east_landing",Vector2(8256,2302)],
			["03_middle_junction",Vector2(8256,2814)],["04_ruined_street_rise",Vector2(7808,2966)],
			["05_broken_street_turn",Vector2(7008,3134)],["06_lower_courtyard",Vector2(7424,3582)],
			["07_east_base",Vector2(8256,4222)],["08_archive_join",Vector2(6848,2302)]]:
			player.reset_after_map_fall(sample[1])
			await step(18)
			await capture(sample[0])
		await end_east_test(false)
		return
	check(is_instance_valid(level.entrance_art.get_node_or_null("EastStreet/UpperCoveredGallery")),"The east gallery has its new open veranda")
	check(is_instance_valid(level.entrance_art.get_node_or_null("EastStreet/LowerCraftCourtyard")),"The lower street has a grounded rear courtyard")
	check(is_instance_valid(level.get_node_or_null("VisibleCavernGates")),"Original gates draw above the painted depth planes")
	var latch_checked:=false
	var east_turns:=0
	for goal in ["w36","w28","w18","c20","c12","c33","archive_return","e33","e41","e33","e41","e53","e41",
		"route_20_5","route_20_4","route_20_3","route_20_2","route_20_1","route_20_0","e53","c53","c37","entry"]:
		if not await navigate(goal):
			await end_east_test(true)
			return
		if goal in ["archive_return","e33","e41","e53","e64"]:
			check(standing() and not player.is_in_deep_water(),"Existing dry east-street landing remains reachable: "+goal)
			await capture("route_"+goal)
		if goal=="e41": east_turns+=1
		if goal=="e41" and east_turns==3 and not latch_checked:
			check(not level.open_doors.S2,"The middle shortcut starts closed")
			if not await walk(Vector2(7296,2814)):
				await end_east_test(true)
				return
			await capture("middle_gate_closed")
			await interact()
			check(level.open_doors.S2,"Real E input from the east releases the original middle latch")
			await capture("middle_gate_open")
			if not await walk(Vector2(7088,2814)):
				await end_east_test(true)
				return
			check(player.position.x<7168,"The released shortcut is physically traversable")
			latch_checked=true
			if not await walk(level.marker("e41")):
				await end_east_test(true)
				return
		if goal=="e53":
			if not await walk(Vector2(7424,3582)):
				await end_east_test(true)
				return
			await capture("lower_courtyard")
			await jump_in_place("lower east courtyard")
			if not await walk(level.marker("e53")):
				await end_east_test(true)
				return
	check(level.drowned_count==0,"The complete east-street circuit has no drowning or reset")
	check(player.position.distance_to(level.start)<16,"The real-input east circuit returns to the original entrance")
	await end_east_test(true)


func end_east_test(continuous: bool) -> void:
	release()
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":continuous,"fixed_camera_samples":not continuous,
		"position_resets":0 if continuous else 8,"tour":tour,
		"final_position":[player.position.x,player.position.y],"drowned":level.drowned_count}
	if "_east_patch" in level.entrance_art:
		var patch=level.entrance_art._east_patch
		report.east_patch={"air":patch.air_count,"contours":patch.contour_count,"roads":patch.road_count,"timbers":patch.timber_segments.size()}
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
	finish("CAVERN EAST STREET ART")

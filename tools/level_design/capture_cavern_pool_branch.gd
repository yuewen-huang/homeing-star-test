extends "capture_cavern_central_well.gd"
## W2 only. Fixed art samples reset position; the normal circuit never does.
var fixed_position_resets := 4


func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size=Vector2i(640,360)
		root.size=Vector2i(640,360)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_pool_branch_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_dry_bank",Vector2(8768,2814)],["02_waterline",Vector2(9100,2850)],
			["03_lower_pool",Vector2(9088,3380)],["04_drain_alcove",Vector2(9480,3510)]]:
			player.reset_after_map_fall(sample[1])
			await step(18)
			await capture(sample[0])
		await end_pool_test(false)
		return
	check(is_instance_valid(level.entrance_art.get_node_or_null("PoolBranch/DryDrawingBank")),"A grounded dry bank marks the local water entrance")
	check(is_instance_valid(level.entrance_art.get_node_or_null("PoolBranch/OldDrainAlcove")),"The side recess has its own rear drainage masonry")
	for goal in ["w36","w28","w18","c20","c12","c33","archive_return","e33","e41","pool_bank"]:
		if not await navigate(goal):
			await end_pool_test(true)
			return
	check(standing() and not player.is_in_deep_water(),"The existing pool bank is reachable on dry ground")
	await capture("bank_arrival")
	for item in level.layout.water_itineraries.W2:
		var target:=Vector2(float(item[0]),float(item[1]))
		var mode: String=item[2]
		var reached:=await walk(target) if mode=="walk" else await swim_to(target,mode)
		if not reached:
			await end_pool_test(true)
			return
		if target.x==9472:
			check(player.is_in_deep_water(),"Real swim input reaches the submerged side recess")
			await capture("recess_arrival")
	check(standing() and not player.is_in_deep_water(),"Real swim/jump input returns to the same dry bank")
	check(level.oxygen.fraction()>0.99,"The original breathing surface refills oxygen")
	check(longest_swim<20.0 and min_oxygen>0,"The local dive fits the unchanged oxygen budget")
	await capture("bank_return")
	for goal in ["e41","e53","c53","c37","entry"]:
		if not await navigate(goal):
			await end_pool_test(true)
			return
	check(level.drowned_count==0,"The continuous local round trip has no drowning")
	check(player.position.distance_to(level.start)<16,"The real-input circuit returns to the original entrance")
	await end_pool_test(true)


func end_pool_test(continuous: bool) -> void:
	release()
	var report={"checks":checks,"failures":failures,"game_seconds":frames/60.0,
		"continuous_real_input":continuous,"fixed_camera_samples":not continuous,
		"position_resets":0 if continuous else fixed_position_resets,"tour":tour,
		"final_position":[player.position.x,player.position.y],"drowned":level.drowned_count,
		"minimum_oxygen":min_oxygen,"longest_swim_seconds":longest_swim}
	if "_pool_patch" in level.entrance_art:
		var patch=level.entrance_art._pool_patch
		report.pool_patch={"air":patch.air_count,"contours":patch.contour_count,"roads":patch.road_count,"timbers":patch.timber_segments.size()}
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
	finish("CAVERN W2 POOL ART")

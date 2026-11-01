extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Continuous local art review using ordinary input, without position resets.


func run() -> void:
	use_memory_progress()
	output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_west_market_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	check(is_instance_valid(level.entrance_art.get_node_or_null("WestMerchantShop")),"The west street uses the newly painted merchant ruin")
	await capture("01_entrance_preserved")
	if not await navigate("gate"):
		await end_market_test()
		return
	if not await walk(Vector2(2304,2558)):
		await end_market_test()
		return
	check(not player.is_in_deep_water() and standing(),"The former art boundary is now a dry continuous merchant street")
	await capture("02_west_merchant_shop")
	if not await walk(level.marker("w36")):
		await end_market_test()
		return
	nav_at="w36"
	check(standing(),"The open street-well bridge retains its real landing")
	await capture("03_open_street_well")
	if not await navigate("route_1_0"):
		await end_market_test()
		return
	await capture("04_short_joinery_landing")
	if not await navigate("w28"):
		await end_market_test()
		return
	check(standing() and not player.is_in_deep_water(),"The painted collapsed roof and ordinary jumps reach the upper landing")
	await capture("05_upper_return")
	if not await navigate("w36"):
		await end_market_test()
		return
	check(standing(),"The separate drop returns to the middle bridge without hitting new geometry")
	await capture("06_return_bridge")
	if not await navigate("street_split"):
		await end_market_test()
		return
	await capture("07_next_art_boundary")
	if not await navigate("gate"):
		await end_market_test()
		return
	await capture("08_return_gate")
	if not await navigate("entry"):
		await end_market_test()
		return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The local art round trip preserves dry traversal and oxygen")
	check(player.position.distance_to(level.start)<16,"The real-input tour returns to the original entrance without warps")
	await end_market_test()


func end_market_test() -> void:
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
	finish("CAVERN WEST MARKET ART")

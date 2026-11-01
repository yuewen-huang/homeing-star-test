extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Continuous trading-street/cellar review using real input, without warps.


func run() -> void:
	use_memory_progress()
	output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_trade_street_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	nav_points=level.layout.navigation.points
	nav_links=level.layout.navigation.links
	await step(18)
	check(is_instance_valid(level.entrance_art.get_node_or_null("TradeStreet/MerchantTradingGallery")),"The long street uses the new low Chinese trading gallery")
	await capture("01_entrance_preserved")
	if not await navigate("w36"):
		await end_street_test()
		return
	if not await walk(Vector2(3712,2558)):
		await end_street_test()
		return
	check(standing() and not player.is_in_deep_water(),"The old west-street junction remains a dry continuous approach")
	await capture("02_western_trading_approach")
	if not await navigate("street_split"):
		await end_street_test()
		return
	await capture("03_cellar_mouth")
	if not await navigate("street_side"):
		await end_street_test()
		return
	check(standing() and not player.is_in_deep_water(),"The two existing ladder segments still enter the dry cargo cellar")
	await capture("04_cargo_cellar")
	await jump_in_place("cargo cellar")
	if not await navigate("street_split"):
		await end_street_test()
		return
	check(standing() and absf(player.position.y-2558)<4,"The unchanged cellar ladders return to the main street")
	if not await walk(Vector2(4832,2558)):
		await end_street_test()
		return
	await capture("05_merchant_gallery")
	if not await walk(Vector2(5290,2558)):
		await end_street_test()
		return
	await capture("06_gallery_east_end")
	if not await navigate("c37"):
		await end_street_test()
		return
	check(standing() and not player.is_in_deep_water(),"The full merchant street reaches the central shaft mouth on the original deck")
	await capture("07_central_shaft_mouth")
	await jump_in_place("central shaft street deck")
	if not await navigate("entry"):
		await end_street_test()
		return
	check(level.drowned_count==0 and level.oxygen.fraction()>0.99,"The street/cellar circuit preserves dry movement and oxygen")
	check(player.position.distance_to(level.start)<16,"The real-input circuit returns to the original entrance without resets")
	await end_street_test()


func end_street_test() -> void:
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
	finish("CAVERN TRADE STREET ART")

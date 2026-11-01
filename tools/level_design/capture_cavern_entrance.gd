extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Real-input local art review; no position reset during this entrance tour.

func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_entrance_art_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	nav_links = level.layout.navigation.links
	await step(18)
	check(is_instance_valid(level.entrance_art),"Entrance uses the new production art component")
	check(not player.is_in_deep_water(),"The city approach is dry")
	await capture("01_approach")
	if not await walk(level.vector(nav_points.entry_ramp_top)):
		await end_entry_test()
		return
	var slope: Array = level.layout.ramps[-1]
	var a: Vector2 = level.vector(slope[0])
	var b: Vector2 = level.vector(slope[1])
	if not await walk(a.lerp(b,0.65)):
		await end_entry_test()
		return
	await capture("02_threshold")
	if not await walk(level.marker("gate")):
		await end_entry_test()
		return
	await capture("03_gate")
	if not await walk(Vector2(2250,level.marker("gate").y)):
		await end_entry_test()
		return
	await capture("04_art_boundary")
	if not await walk(level.marker("gate")):
		await end_entry_test()
		return
	nav_at = "gate"
	if not await navigate("gate_side"):
		await end_entry_test()
		return
	await capture("05_under_gate")
	if not await navigate("gate"):
		await end_entry_test()
		return
	check(not player.is_in_deep_water(),"The hatch and service stair remain dry and usable")
	check(level.drowned_count==0,"Entrance art preserves the real traversal")
	await capture("06_return_gate")
	await end_entry_test()


func capture(label: String) -> void:
	if not "--edge-compare" in OS.get_cmdline_user_args():
		await super.capture(label)
		return
	if DisplayServer.get_name()=="headless": return
	# Same real position, camera and pose for the two material settings.
	var previous_mode := player.process_mode
	player.process_mode=Node.PROCESS_MODE_DISABLED
	level.snap_camera()
	for enabled in [false,true]:
		level.entrance_art.set_edge_blend_enabled(enabled)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label+("_blended" if enabled else "_hard")+".png"))
	level.entrance_art.set_edge_blend_enabled(true)
	player.process_mode=previous_mode


func end_entry_test() -> void:
	release()
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream = null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("CAVERN ENTRANCE ART")

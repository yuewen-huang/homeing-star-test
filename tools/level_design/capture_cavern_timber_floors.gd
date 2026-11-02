extends "capture_cavern_final_art.gd"
## Identical native fixed views for timber-depth reviews; --tour reuses real input.

func run() -> void:
	if "--tour" in OS.get_cmdline_user_args():
		await super.run()
		return
	use_memory_progress()
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await step(18)
	level.set_process(false)
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.visible=false
	for layer in root.find_children("*","CanvasLayer",true,false): layer.visible=false
	level.camera.position_smoothing_enabled=false
	for sample in [["01_a4_a5_west_stairs",Vector2(3250,2160)],
		["02_a6_bell_floors",Vector2(2180,1140)],
		["03_a11_central_return",Vector2(5780,3460)],
		["04_a17_east_ramps",Vector2(7640,3090)],
		["05_a12_archive_steps",Vector2(6880,1760)],
		["06_a26_forecourt_steps",Vector2(7370,5182)],
		["07_a3_hatch_deck",Vector2(1510,2860)],
		["08_stone_timber_joint",Vector2(7424,2302)]]:
		player.reset_after_map_fall(sample[1])
		level.camera.position=sample[1]-Vector2(0,160)
		level.camera.reset_smoothing()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join(sample[0]+".png"))==OK,"Native timber view: "+sample[0])
	check(CavernEntranceArt.WALKWAY.get_width()<=512,"Runtime timber uses a low-detail texture")
	check(CavernEntranceArt.WALKWAY.get_image().has_mipmaps(),"Runtime timber includes smaller filtered levels")
	# Eight explicit fixed poses, not a continuous traversal tour.
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("CAVERN TIMBER FIXED VIEWS")

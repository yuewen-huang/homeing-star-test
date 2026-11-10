extends "../../tests/support/harness.gd"
## Interactive whole-map preview with abilities/progress isolated in memory.
const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"


func run() -> void:
	use_memory_progress()
	var level := (load(SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	if "--toad" in OS.get_cmdline_user_args():
		level.player.reset_after_map_fall(level.bronze_toad.RETRY_AT)
		level.snap_camera()
		root.title = "归航星 · A25 青铜金蟾试玩"
		print("A25_PLAYTEST_READY")
		return
	if "--edges" in OS.get_cmdline_user_args():
		await capture_edges(level)
		await close_capture(level)
		return
	if "--routes" in OS.get_cmdline_user_args():
		await capture_routes(level)
	if not "--overview" in OS.get_cmdline_user_args() and not "--routes" in OS.get_cmdline_user_args():
		return
	for i in 12: await physics_frame
	level.set_process(false)
	for layer in level.player.find_children("*", "CanvasLayer", true, false): layer.visible = false
	level.player.visible = false
	level.camera.limit_left = -1024
	level.camera.limit_top = -1024
	level.camera.limit_right = int(level.bounds.end.x) + 1024
	level.camera.limit_bottom = int(level.bounds.end.y) + 1024
	level.camera.position_smoothing_enabled = false
	level.camera.zoom = Vector2(0.115, 0.115)
	level.camera.position = level.bounds.get_center()
	level.camera.reset_smoothing()
	await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sunken_cavern_graybox_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	var target := output.path_join("03_whole_graybox.png")
	root.get_texture().get_image().save_png(target)
	await close_capture(level)


func capture_routes(level: Node2D) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	var nav: Dictionary = level.layout.navigation.points
	var west: Vector2 = level.vector(nav.route_1_3).lerp(level.vector(nav.route_1_4),0.5)
	var east: Vector2 = level.vector(nav.route_20_4).lerp(level.vector(nav.route_20_5),0.5)
	for sample in [["west_loft",west],["central_atrium",level.marker("c41")],["east_street",east],["foundation",level.marker("w60")]]:
		# These resets are render samples, never evidence of route reachability.
		level.player.reset_after_map_fall(sample[1])
		for i in 12: await physics_frame
		level.snap_camera()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(sample[0]+".png"))


func capture_edges(level: Node2D) -> void:
	var output := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_edges_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	for sample in [["central", "c37"], ["gate", "gate"], ["lower", "dry_base"], ["water", "vault"]]:
		level.player.reset_after_map_fall(level.marker(sample[1]))
		for i in 18: await physics_frame
		level.snap_camera()
		for enabled in [false, true]:
			level.rock_edges_enabled = enabled
			level.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var suffix := "soft" if enabled else "hard"
			root.get_texture().get_image().save_png(output.path_join(sample[0] + "_" + suffix + ".png"))


func close_capture(level: Node2D) -> void:
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	for audio in root.find_children("*", "AudioStreamPlayer2D", true, false):
		audio.stop()
		audio.stream = null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("SUNKEN CAVERN OVERVIEW")

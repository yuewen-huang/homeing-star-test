extends "../../tests/support/harness.gd"
## Interactive whole-map preview with abilities/progress isolated in memory.
const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"


func run() -> void:
	use_memory_progress()
	var connected_route := "--zhenxi-route" in OS.get_cmdline_user_args()
	var level := (load(SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	if connected_route:
		level.player.reset_after_map_fall(level.marker("pool_bank"))
		level.snap_camera()
		root.title = "归航星 · 镇西门 · 正式美术试玩"
		print("ZHENXI_CONNECTED_ROUTE_READY")
		return
	if "--zhenxi-sluice-return" in OS.get_cmdline_user_args():
		await preview_return_cut(level)
		return
	if "--zhenxi-aftermath" in OS.get_cmdline_user_args():
		await stage_court(level)
		var gallery: Node2D = level._hidden_gallery
		gallery._on_general_defeated()
		gallery.place_at_victory_return()
		level.snap_camera()
		root.title = "归航星 · 镇西门战后试玩"
		print("ZHENXI_AFTERMATH_PLAYTEST_READY")
		return
	if "--flag-defense" in OS.get_cmdline_user_args():
		await stage_court(level)
		var gallery: Node2D = level._hidden_gallery
		var guard := gallery.get_node("GeneralStart") as Marker2D
		level.player.reset_after_map_fall(level.to_local(guard.global_position - Vector2(340, 0)))
		gallery._start_battle()
		gallery.general.reset_fight(guard.global_position, 2, false)
		# The preview begins after the two volleys of the second phase.
		gallery.general._threshold_index = 2
		gallery.general.combat_stats.set_health_ratio(0.0)
		level.snap_camera()
		root.title = "归航星 · 镇西门守旗试玩"
		print("ZHENXI_FLAG_DEFENSE_PLAYTEST_READY")
		return
	if "--hidden-general" in OS.get_cmdline_user_args():
		await stage_court(level)
		var retry := level._hidden_gallery.get_node("ArenaRetry") as Marker2D
		level.player.reset_after_map_fall(level.to_local(retry.global_position))
		level.snap_camera()
		root.title = "归航星 · 镇西门残甲将军试玩"
		print("ZHENXI_GENERAL_PLAYTEST_READY")
		return
	if "--gate-art" in OS.get_cmdline_user_args():
		await stage_court(level)
		root.title = "归航星 · 镇西门美术试玩"
		print("ZHENXI_ART_PLAYTEST_READY")
		return
	if "--hidden-door" in OS.get_cmdline_user_args():
		level.player.reset_after_map_fall(level.marker("pool_bank"))
		level.snap_camera()
		root.title = "归航星 · A18 水下隐藏入口试玩"
		print("A18_HIDDEN_DOOR_PLAYTEST_READY")
		return
	if "--west-shaft-return" in OS.get_cmdline_user_args():
		level.player.reset_after_map_fall(level.marker("dry_base"))
		level.snap_camera()
		root.title = "归航星 · A22 正式美术试玩"
		print("WEST_SHAFT_RETURN_PLAYTEST_READY")
		return
	if "--west-shafts" in OS.get_cmdline_user_args():
		level.player.reset_after_map_fall(level.marker("w60"))
		level.snap_camera()
		root.title = "归航星 · A4–A19 / A22 西井试玩"
		print("WEST_SHAFTS_PLAYTEST_READY")
		return
	if "--toad" in OS.get_cmdline_user_args():
		if "--stake-chain" in OS.get_cmdline_user_args():
			level.bronze_toad.engagement_changed.connect(func(active: bool) -> void:
				if active:
					# Pop order: throw, fracture slam, then the other two normal combinations.
					level.bronze_toad._bag.assign([1, 2, 3, 0])
					level.bronze_toad._fracture_next = true)
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
		root.title = "归航星 · 沉没古城 · 全图试玩"
		print("SUNKEN_CAVERN_PLAYTEST_READY")
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


static func stage_court(level: SunkenCavern) -> void:
	await level._cover_zhenxi_crossing()
	if level._hidden_gallery == null:
		level._prepare_hidden_gallery()
	level._inside_gallery = true
	level._set_gallery_music(true)
	level._arrive_at_zhenxi_court(^"Arrival")
	await level._uncover_zhenxi_crossing()


func preview_return_cut(level: SunkenCavern) -> void:
	await stage_court(level)
	var gallery: Node2D = level._hidden_gallery
	var progress := root.get_node("SaveProgress") as SaveProgressService
	progress.finish_cinematic(level.ARRIVAL_COMIC_ID, true)
	gallery._on_general_defeated()
	gallery.place_at_victory_return()
	var departure: Marker2D = level._gallery_exit
	var a18_bank: Vector2 = level.marker("pool_bank")
	level.snap_camera()
	root.title = "归航星 · 镇西门战后回程预演"
	print("ZHENXI_SLUICE_RETURN_READY")
	if not "--verify" in OS.get_cmdline_user_args():
		return

	var lan: LanPlayer = level.player
	check(not level._can_use_hidden_door(), "The return cut is outside the recovery area at the lamp")
	var approach_x := level.to_local(departure.global_position).x - 40.0
	Input.action_press(&"ui_right")
	for frame in 320:
		if lan.position.x >= approach_x:
			break
		await physics_frame
	Input.action_release(&"ui_right")
	check(level._can_use_hidden_door(), "Lan can walk east from the lamp to the main gate")
	var interact_key := InputEventAction.new()
	interact_key.action = &"interact"
	interact_key.pressed = true
	Input.parse_input_event(interact_key)
	await wait_frames(2)
	interact_key.pressed = false
	Input.parse_input_event(interact_key)
	for frame in 90:
		if level._passage_comic != null and not level._passage_comic.get("covered_by_fade"):
			break
		await physics_frame
	check(is_instance_valid(level._passage_comic), "The departure comic starts at the steps")
	var skip := InputEventKey.new()
	skip.physical_keycode = KEY_ESCAPE
	skip.pressed = true
	Input.parse_input_event(skip)
	await wait_frames(2)
	skip.pressed = false
	Input.parse_input_event(skip)
	for frame in 100:
		if not level._inside_gallery and not level._crossing_door:
			break
		await physics_frame
	check(not level._inside_gallery and level.player == lan, "The real departure interaction returns the same Lan to A18")
	check(lan.position.distance_to(a18_bank) <= 24.0 and not lan.is_in_deep_water(),
		"The return lands on the A18 dry bank, clear of the submerged entrance")
	expect_save_untouched()
	finish("ZHENXI SLUICE RETURN")


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

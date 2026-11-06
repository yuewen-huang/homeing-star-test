extends "../../support/harness.gd"
var room: Chapter1DeerBossRoom

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	use_memory_progress()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene = packed
	root.add_child(room)
	current_scene = room
	await wait_frames(5)
	room.encounter._spawn_phase(2, 1460)
	room.encounter.start()
	await wait_frames(5)
	check(room.get_node("Camera2D").zoom.is_equal_approx(room._normal_camera_zoom), "Root phase keeps the normal camera scale")
	var left_camera: float = room.get_node("Camera2D").position.x
	room.player.position.x = 1800
	await wait_frames(3)
	check(room.get_node("Camera2D").position.x > left_camera + 300, "Normal-scale root camera follows traversal rather than clipping offscreen")
	await snap("root_normal_camera")
	room.encounter._spawn_phase(3, 1460)
	room.encounter.start()
	var boss = room.deer
	boss.manual_control = true
	boss.cancel_duel()
	room.player.position = Vector2(1100,555)
	boss.start_scene_move(&"forest_raise")
	while boss.age < .70: await physics_frame
	await snap("forest_stomp_warning")
	while boss.age < 1.05: await physics_frame
	await snap("forest_stomp_live")
	boss.cancel_duel()
	boss.position = Vector2(1500,555)
	boss.vine_far = 1040.0
	boss.start_vine_return()
	while boss.age < .30: await physics_frame
	await snap("forest_low_vine_warning")
	while boss.age < .60: await physics_frame
	await snap("forest_low_vine_live")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for iteration in 3:
		boss.cancel_duel()
		boss.start_scene_move(&"sky_cast")
		var samples: Array[float] = []
		var draws: Array[float] = []
		var captured := false
		var last := Time.get_ticks_usec()
		while boss.move == &"sky_cast":
			await process_frame
			var now := Time.get_ticks_usec()
			if boss.age > .9 and boss.age < 2.2:
				samples.append((now-last)/1000.0)
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			last = now
			if iteration == 0 and not captured and boss.age > 1.62:
				captured = true
				await snap("forest_sky_live")
				last = Time.get_ticks_usec()
		samples.sort()
		draws.sort()
		check(not samples.is_empty(), "Ultimate produced real rendered samples")
		if not samples.is_empty(): print("VINE_PERF run=", iteration, " n=", samples.size(), " median_ms=", samples[samples.size()/2], " p95_ms=", samples[int(samples.size()*.95)], " max_ms=", samples.back(), " draw_p95=", draws[int(draws.size()*.95)])
	room.encounter.stop()
	current_scene = null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER FOREST VISUAL AND FRAME TIME")

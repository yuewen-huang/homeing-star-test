extends "../../tests/support/harness.gd"

func run() -> void:
	use_memory_progress()
	var level := (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await wait_frames(20)
	level.set_process(false)
	level.player.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	for view in [
		["outer_gate",Vector2(360,880),Vector2(760,670)],
		["gate_air_room",Vector2(1080,770),Vector2(1080,660)],
		["inner_waterway",Vector2(1660,880),Vector2(1280,670)],
	]:
		level.player.reset_after_map_fall(view[1])
		if view[0] != "gate_air_room":
			level.player.air_state = LanPlayer.AirState.SWIMMING
			level.player.facing_direction = 1
			LanSwimMotor.play_swim_animation(level.player,LanSwimMotor.ANIM_IDLE)
		level.camera.position = view[2]
		level.camera.reset_smoothing()
		level.queue_redraw()
		await wait_frames(3)
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sunken_city_gate_20261031/art")
		DirAccess.make_dir_recursive_absolute(folder)
		check(root.get_texture().get_image().save_png(folder.path_join(view[0]+".png"))==OK,"Native gate capture: "+view[0])
	expect_save_untouched()
	finish("SUNKEN CITY GATE ART")

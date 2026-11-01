extends "../../tests/support/harness.gd"

func run() -> void:
	use_memory_progress()
	var level := (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await wait_frames(15)
	level.set_process(false)
	level.player.set_physics_process(false)
	level.oxygen.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	var folder := OS.get_environment("HOMING_STAR_MERCHANT_CAPTURE")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/city_merchant_hall_20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	for view in [
		["01_approach", Vector2(2500, 900), Vector2(2820, 640)],
		["02_exterior", Vector2(2560, 900), Vector2(3360, 620)],
		["02b_entering", Vector2(2700, 900), Vector2(2820, 640), 0.15, false],
		["03_interior", Vector2(3200, 760), Vector2(3360, 620)],
		["04_east_exit", Vector2(4200, 900), Vector2(3840, 680)],
		["05_left_interior_joint", Vector2(2830, 825), Vector2(2820, 660)],
		["06_right_interior_joint", Vector2(3890, 825), Vector2(3840, 660)],
	]:
		level.player.reset_after_map_fall(view[1])
		var inside: bool = view[0] == "03_interior"
		if not inside:
			level.player.air_state = LanPlayer.AirState.SWIMMING
			LanSwimMotor.play_swim_animation(level.player, LanSwimMotor.ANIM_IDLE)
		level.gate_room.track(level.player.position + LanSwimMotor.BODY_PROBE, 0.0, true)
		var blend_delta: float = view[3] if view.size() > 3 else 0.0
		var snap: bool = view[4] if view.size() > 4 else true
		level.merchant_hall.track(level.player.position + LanSwimMotor.BODY_PROBE, blend_delta, snap)
		level.gate_room.terrain_depth.set_contact(level.player.position, inside)
		level.camera.position = view[2]
		level.camera.reset_smoothing()
		level.queue_redraw()
		await wait_frames(3)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join(view[0] + ".png")) == OK, "Native warehouse capture " + view[0])
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.stop()
			node.stream = null
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	finish("CITY MERCHANT HALL CAPTURE")

extends "../../tests/support/harness.gd"

func run() -> void:
	use_memory_progress()
	var level := (load("res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await wait_frames(12)
	level.set_process(false)
	level.player.set_physics_process(false)
	level.oxygen.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	level.camera.position = Vector2(980, 620)
	level.camera.reset_smoothing()
	var folder := OS.get_environment("HOMING_STAR_GATE_CAPTURE")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/city_gate_painted_20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	for view in [
		["01_outside", Vector2(480, 900), 0.0, true],
		["02_threshold", Vector2(660, 900), 0.15, false],
		["03_inside", Vector2(1080, 770), 0.3, false],
		["04_right_exit", Vector2(1620, 900), 0.3, false],
	]:
		level.player.reset_after_map_fall(view[1])
		if view[0] != "03_inside":
			level.player.air_state = LanPlayer.AirState.SWIMMING
			LanSwimMotor.play_swim_animation(level.player, LanSwimMotor.ANIM_IDLE)
		level.gate_room.track(level.player.position + LanSwimMotor.BODY_PROBE, view[2], view[3])
		level.gate_room.terrain_depth.set_contact(level.player.position, view[0] == "03_inside")
		level.queue_redraw()
		await wait_frames(3)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join(view[0] + ".png")) == OK, "Captured " + view[0])
	level.player.reset_after_map_fall(Vector2(1080, 770))
	level.gate_room.track(level.player.position + LanSwimMotor.BODY_PROBE, 0.0, true)
	level.gate_room.terrain_depth.set_contact(level.player.position, true)
	level.camera.position = Vector2(980, 700)
	level.camera.reset_smoothing()
	level.queue_redraw()
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("05_stone_floors.png")) == OK, "Captured stone floor top, face and shared bank corners")
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.stop()
			node.stream = null
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	finish("CITY GATE CUTAWAY CAPTURE")

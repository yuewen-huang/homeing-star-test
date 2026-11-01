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
	var folder := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/gate_street_transition_20261101")
	DirAccess.make_dir_recursive_absolute(folder)
	for view in [
		["01_gate_to_street", Vector2(1730, 900), Vector2(1600, 700)],
		["02_ruined_street", Vector2(2140, 900), Vector2(1920, 700)],
		["03_gallery_entry", Vector2(2420, 900), Vector2(1920, 620)],
	]:
		level.player.reset_after_map_fall(view[1])
		level.player.air_state = LanPlayer.AirState.SWIMMING
		LanSwimMotor.play_swim_animation(level.player, LanSwimMotor.ANIM_IDLE)
		level.gate_room.track(level.player.position + LanSwimMotor.BODY_PROBE, 0.0, true)
		level.gate_room.terrain_depth.set_contact(level.player.position, false)
		level.camera.position = view[2]
		level.camera.reset_smoothing()
		level.queue_redraw()
		await wait_frames(3)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join(view[0] + ".png")) == OK, "Native capture " + view[0])
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.stop()
			node.stream = null
	level.queue_free()
	await wait_frames(8)
	expect_save_untouched()
	finish("GATE STREET TRANSITION CAPTURE")

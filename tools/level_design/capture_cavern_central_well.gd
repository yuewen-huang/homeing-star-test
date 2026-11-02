extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Central-shaft artwork review. Normal mode is a continuous real-input circuit;
## --poses is only a set of fixed-camera visual samples, never route evidence.


func run() -> void:
	use_memory_progress()
	if "--small" in OS.get_cmdline_user_args():
		root.content_scale_size = Vector2i(640,360)
		root.size = Vector2i(640,360)
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_central_well_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	nav_links = level.layout.navigation.links
	await step(18)
	if "--poses" in OS.get_cmdline_user_args():
		for sample in [["01_crown", "crown"], ["02_upper_well", "c12"], ["03_hoist", "c37"], ["04_lower_join", "c53"], ["05_lower_well", "c60"], ["06_well_bottom", "c75"], ["07_archive_join", "archive"], ["08_wheel", "c41"]]:
			player.reset_after_map_fall(level.marker(sample[1]))
			await step(18)
			await capture(sample[0])
		await end_well_test(false)
		return
	check(is_instance_valid(level.entrance_art.get_node_or_null("CentralWell/WellCrownPavilion")), "The crown has its own newly painted low pavilion")
	check(is_instance_valid(level.entrance_art.get_node_or_null("CentralWell/AncientWellHoist")), "One rear hoist connects the central shaft visually")
	check(level.layout.ladders.size() == 10, "Artwork adds no ladders or route geometry")
	await capture("00_entrance_preserved")
	# The lower circuit follows the authored separate return: west dry route
	# -> well bottom -> rising remnants, rather than falling down the up route.
	for goal in ["w36", "w28", "w18", "c20", "c12", "crown", "c12", "c33", "c37", "c41", "c53", "w53", "dry_turn", "dry_base", "c75", "c60", "c53", "c37", "entry"]:
		if not await navigate(goal):
			await end_well_test(true)
			return
		if goal in ["crown", "c12", "c33", "c37", "c41", "c53", "c60", "c75"]:
			check(standing() and not player.is_in_deep_water(), "Existing dry landing remains reachable: " + goal)
			await capture("route_" + goal)
		if goal in ["crown", "c37"]: await jump_in_place(goal)
	check(level.drowned_count == 0 and level.oxygen.fraction() > 0.99, "The central-well circuit leaves water and oxygen behavior unchanged")
	check(player.position.distance_to(level.start) < 16, "The continuous circuit returns to the real entrance without resets")
	await end_well_test(true)


# Local input driver for this art circuit; keep the historical whole-map
# regression unchanged. Uses normal game inputs only, no actor state writes.
func descend(target: Vector2, chute_x: float = NAN) -> bool:
	release()
	var exit_x := player.position.x
	var launch_y := player.position.y
	var exit_direction := 1.0
	var downhill_direction := 0.0
	var was_grounded := false
	for i in int(maxf(10.0,absf(target.y-launch_y)/90.0+10.0)*60):
		Input.action_release(&"jump")
		var grounded := standing()
		if grounded and player.air_state != LanPlayer.AirState.GROUNDED:
			release()
			was_grounded = false
			await step(1)
			continue
		if grounded and absf(player.position.y - target.y) < 5:
			release()
			return await walk(target)
		if grounded:
			launch_y = player.position.y
			# Find the connected support under the actual feet and walk off its
			# nearest free lip. No position/state/velocity assignment is used.
			var spans: Array[Vector2] = []
			for item in level.layout.floors + level.layout.platforms:
				if absf(float(item[1]) - player.position.y) < 5:
					spans.append(Vector2(float(item[0]), float(item[0]) + float(item[2])))
			for ramp in level.layout.ramps:
				var a: Vector2 = level.vector(ramp[0])
				var b: Vector2 = level.vector(ramp[1])
				if player.position.x >= minf(a.x,b.x) and player.position.x <= maxf(a.x,b.x):
					var y := lerpf(a.y,b.y,(player.position.x-a.x)/(b.x-a.x))
					if absf(y-player.position.y) < 5:
						spans.append(Vector2(minf(a.x,b.x),maxf(a.x,b.x)))
						if absf(a.y-b.y)>20:
							downhill_direction = signf(a.x-b.x) if a.y>b.y else signf(b.x-a.x)
			var bounds := Vector2(player.position.x, player.position.x)
			for repeat in spans.size() + 1:
				for span in spans:
					if span.x <= bounds.y + 2 and span.y >= bounds.x - 2:
						bounds.x = minf(bounds.x,span.x)
						bounds.y = maxf(bounds.y,span.y)
			var exits := [bounds.x - 20, bounds.y + 20]
			var aim := player.position.x if is_nan(chute_x) else chute_x
			exits.sort_custom(func(a: float,b: float): return absf(a-aim) < absf(b-aim))
			if not is_zero_approx(downhill_direction):
				exits.sort_custom(func(a: float,b: float): return a*downhill_direction > b*downhill_direction)
			for candidate in exits:
				var clear := true
				for dy in [6,40,62]:
					var inside := false
					for space in level.layout.spaces:
						for r in space.rects:
							if level.rect(r).has_point(Vector2(candidate,player.position.y-dy)): inside = true
					if not inside: clear = false
				if clear:
					exit_x = candidate
					exit_direction = signf(candidate - player.position.x)
					break
			# Leave a narrow resting beam with a deliberate normal jump. A
			# one-frame walk-off can recontact its lip and start the protected
			# landing roll, repeatedly returning this input driver to the beam.
			var exit_room := INF
			for span in spans:
				if exit_direction > 0 and span.x > bounds.y+2: exit_room=minf(exit_room,span.x-bounds.y)
				if exit_direction < 0 and span.y < bounds.x-2: exit_room=minf(exit_room,bounds.x-span.y)
			if (bounds.y-bounds.x <= 128 or absf(exit_x-player.position.x)<55) \
				and exit_room>128 and target.y-player.position.y>80:
				Input.action_press(&"jump")
		var steering_x := exit_x if grounded else target.x
		if not grounded and player.position.y >= launch_y + 24: downhill_direction = 0
		if not grounded and not is_nan(chute_x) and player.position.y < target.y - 32:
			steering_x = chute_x
		if not grounded and player.position.y < launch_y + 64:
			# Keep steering while a deliberate jump rises past a short beam;
			# once falling, brake inside the opening before steering below it.
			# Continuing sideways here crosses a 48px slit onto its opposite lip.
			steering_x = player.position.x + exit_direction * 100 if player.velocity.y < 0 else player.position.x
		var dx := steering_x - player.position.x
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		if absf(dx) > 4: Input.action_press(&"ui_right" if dx > 0 else &"ui_left")
		was_grounded = grounded
		await step(1)
	release()
	check(false, "Drop stuck toward %s at %s state=%s exit=%.1f" % [target,player.position,player.air_state,exit_x])
	await capture("stuck_drop")
	return false


func end_well_test(continuous: bool) -> void:
	release()
	var report = {"checks": checks, "failures": failures, "game_seconds": frames / 60.0,
		"continuous_real_input": continuous, "fixed_camera_samples": not continuous,
		"position_resets": 0 if continuous else 8, "tour": tour,
		"final_position": [player.position.x, player.position.y], "drowned": level.drowned_count}
	if "_well_patch" in level.entrance_art:
		var patch = level.entrance_art._well_patch
		report.terrain_patch = {"air": patch.air_count, "contours": patch.contour_count, "roads": patch.road_count, "timbers": patch.timber_segments.size()}
	for type in ["AudioStreamPlayer", "AudioStreamPlayer2D"]:
		for audio in root.find_children("*", type, true, false):
			audio.stop()
			audio.stream = null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(output.path_join("validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	finish("CAVERN CENTRAL WELL ART")

extends "../../../support/harness.gd"
## One continuous real-input tour; the player is never warped during traversal.
const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
const ACTIONS := [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"interact"]
var level: Node2D
var player: LanPlayer
var nav_at := "entry"
var nav_points: Dictionary
var nav_links: Array
var frames := 0
var min_oxygen := 1.0
var swim_time := 0.0
var longest_swim := 0.0
var tour: Array = []
var output := ""
var recovery_depth := 0
var climb_seconds := 0.0
var max_dry_fall := 0.0
var fall_origin := INF


func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sunken_cavern_graybox_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	nav_links = level.layout.navigation.links
	await step(25)
	check(player.position.distance_to(level.start) < 2, "Existing Lan starts at the dry entry floor")
	check(not player.is_in_deep_water(), "Main entry is dry")
	check(level.layout.spaces.size() == 33, "The whole map includes the west loft and east ruined-street return")
	check(level.open_doors.values().count(false) == 2, "Both far-side shortcuts start closed")
	check(level.layout.ladders.size() == 10, "Ten authored interior ladders replace the 48 automatic shaft segments")
	var helper_count := 0
	for label in level.find_children("*", "Label", true, false):
		if not player.is_ancestor_of(label): helper_count += 1
	check(helper_count == 0, "Graybox adds no map/helper text")
	await capture("01_entry")
	var targets := ["gate_side", "w18", "c20", "w18", "bell_top", "bell28", "bell18", "bell28", "w28", "w36", "street_side", "c37", "crown", "c20", "c12", "archive", "archive_return", "e33", "e64", "ante", "boss", "c75", "dry_base", "dry_turn", "dry_base", "c75", "c53", "w53", "c53", "e53", "pool_bank", "c41"]
	for name in targets:
		if not await navigate(name):
			await end_test()
			return
		if name == "c37": await jump_in_place("main landing")
		if name in ["w18", "w36", "c20", "c37", "archive", "e33", "e64", "boss", "dry_base", "c53"]:
			await capture("route_" + name)
	check(not player.is_in_deep_water(), "The complete first dry tour reaches the arena and returns across different levels")
	# A real closed middle gate must block a player trying to cross from the west.
	var gate_s2: Dictionary = level.layout.doors[1]
	if not await walk(Vector2(float(gate_s2.rect[0]) - 24, float(gate_s2.rect[1]) + float(gate_s2.rect[3]))):
		await end_test()
		return
	Input.action_press(&"ui_right")
	await step(100)
	release()
	check(player.position.x < float(gate_s2.rect[0]), "Closed S2 is a physical wall across the whole doorway")
	check(not level.open_shortcut("S2"), "West side cannot release the east-side latch")
	if not await walk(level.marker("c41")):
		await end_test()
		return
	nav_at = "c41"
	if not await navigate("e41"):
		await end_test()
		return
	if not await walk(level.vector(gate_s2.latch) + Vector2(0, 36)):
		await end_test()
		return
	await interact()
	check(level.open_doors.S2, "Real E input from the east releases S2")
	if not await walk(level.marker("e41")):
		await end_test()
		return
	nav_at = "e41"
	if not await navigate("c41"):
		await end_test()
		return
	check(not player.is_in_deep_water(), "Opened middle arch is a direct dry crossing")
	if not await navigate("w1_bank"):
		await end_test()
		return
	if not await navigate("w53") or not await navigate("w1_bank"):
		await end_test()
		return
	if not await water_journey("W1"):
		await end_test()
		return
	nav_at = "vault"
	check(not player.is_in_deep_water(), "W1 leads into a real dry sealed vault")
	await jump_in_place("vault ceiling")
	var gate_s1: Dictionary = level.layout.doors[0]
	if not await walk(level.vector(gate_s1.latch) + Vector2(0, 36)):
		await end_test()
		return
	await interact()
	check(level.open_doors.S1, "Real E input inside the vault releases S1")
	if not await walk(level.marker("vault")):
		await end_test()
		return
	if not await navigate("c60"):
		await end_test()
		return
	if not await navigate("vault"):
		await end_test()
		return
	check(not player.is_in_deep_water(), "Opened S1 allows dry return to the vault")
	await capture("vault_open")
	if not await navigate("pool_bank"):
		await end_test()
		return
	if not await water_journey("W2"):
		await end_test()
		return
	nav_at = "pool_bank"
	check(not player.is_in_deep_water(), "W2 returns to its original dry bank")
	if not await navigate("entry"):
		await end_test()
		return
	check(level.drowned_count == 0, "Whole-map traversal and both water branches finish without drowning")
	check(longest_swim < 14.0, "Measured longest continuous swim remains below 14 s: %.2f" % longest_swim)
	check(min_oxygen > 0.15, "Oxygen margin remains above 15%%: %.3f" % min_oxygen)
	check(player.position.distance_to(level.start) < 16, "Continuous tour returns to its original entry, without warps")
	check(level.visited_spaces.size() == level.layout.spaces.size(), "Every accepted space was physically visited")
	await capture("02_return_entry")
	await end_test()


func step(count: int) -> void:
	for i in count:
		await physics_frame
		frames += 1
		if player.air_state == LanPlayer.AirState.CLIMBING: climb_seconds += 1.0 / 60
		if player.air_state == LanPlayer.AirState.FALLING and not player.is_in_deep_water():
			if is_inf(fall_origin): fall_origin = player.position.y
		elif standing():
			if not is_inf(fall_origin): max_dry_fall = maxf(max_dry_fall,player.position.y-fall_origin)
			fall_origin = INF
		else: fall_origin = INF
		min_oxygen = minf(min_oxygen, level.oxygen.fraction())
		if level.oxygen.mode == UnderwaterOxygen.Mode.SWIMMING:
			swim_time += 1.0 / 60
			longest_swim = maxf(longest_swim, swim_time)
		else: swim_time = 0


func release() -> void:
	for action in ACTIONS: Input.action_release(action)


func standing() -> bool:
	return player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING]


func jump_in_place(label: String) -> void:
	release()
	await step(20)
	var before := player.position
	var top := before.y
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in 85:
		await step(1)
		top = minf(top, player.position.y)
	check(before.y - top > 85, "Existing normal jump has headroom at %s: %.1f px" % [label, before.y - top])
	check(player.position.distance_to(before) < 4 and standing(), "Normal jump lands on the same floor at " + label)


func walk(target: Vector2) -> bool:
	# Cross authored street breaks with the same normal jump a player uses.
	# The game itself has no auto-jump or test navigation logic.
	if absf(target.y - player.position.y) < 5:
		var gaps: Array = []
		var direction := signf(target.x - player.position.x)
		for gap in level.layout.apertures:
			if absf(float(gap[2]) - target.y) > 5: continue
			if direction > 0 and player.position.x < float(gap[0]) and target.x > float(gap[1]): gaps.append(gap)
			if direction < 0 and player.position.x > float(gap[1]) and target.x < float(gap[0]): gaps.append(gap)
		gaps.sort_custom(func(a: Array,b: Array): return float(a[0])*direction < float(b[0])*direction)
		for gap in gaps:
			var before := float(gap[0]) - 8 if direction > 0 else float(gap[1]) + 8
			var after := float(gap[1]) + 8 if direction > 0 else float(gap[0]) - 8
			if not await walk_plain(Vector2(before,target.y)): return false
			if not await hop(Vector2(after,target.y)): return false
	return await walk_plain(target)


func walk_plain(target: Vector2) -> bool:
	release()
	var seconds := absf(player.position.x - target.x) / 150.0 + 5
	for i in int(seconds * 60):
		var dx := target.x - player.position.x
		if absf(dx) < 9 and absf(player.position.y - target.y) < 9 and standing():
			release()
			await step(4)
			return true
		if i > 30 and absf(dx) < 9 and standing() and recovery_depth < 3:
			if player.position.y < target.y - 20:
				recovery_depth += 1
				var recovered := await descend(target)
				recovery_depth -= 1
				return recovered
			if player.position.y > target.y + 20 and player.position.y < target.y + 80:
				recovery_depth += 1
				var recovered := await hop(target)
				recovery_depth -= 1
				return recovered
		if absf(dx) > 5: Input.action_press(&"ui_right" if dx > 0 else &"ui_left")
		else:
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
		await step(1)
	release()
	check(false, "Walk stuck toward %s at %s state=%s" % [target, player.position, player.air_state])
	await capture("stuck_walk")
	return false


func climb(target: Vector2) -> bool:
	release()
	await step(18)
	var dy := target.y - player.position.y
	var action := &"ui_down" if dy > 0 else &"ui_up"
	for i in int((absf(dy) / 140.0 + 4) * 60):
		Input.action_press(action)
		if absf(target.y - player.position.y) < 3 and standing():
			release()
			await step(3)
			return true
		await step(1)
	release()
	check(false, "Climb stuck toward %s at %s state=%s" % [target, player.position, player.air_state])
	await capture("stuck_climb")
	return false


func navigate(goal: String) -> bool:
	var previous := {nav_at: ""}
	var used := {}
	var queue := [nav_at]
	while not queue.is_empty() and not previous.has(goal):
		var current: String = queue.pop_front()
		for link in nav_links:
			if link.has("door") and not level.open_doors[link.door]: continue
			var neighbor: String = link.b if link.a == current else link.a if link.b == current and not link.get("one_way", false) else ""
			if neighbor.is_empty() or previous.has(neighbor): continue
			previous[neighbor] = current
			used[neighbor] = link
			queue.append(neighbor)
	if not previous.has(goal):
		check(false, "Navigation graph has no currently open path to " + goal)
		return false
	var path: Array[String] = []
	var cursor := goal
	while cursor != nav_at:
		path.push_front(cursor)
		cursor = previous[cursor]
	for name in path:
		var target: Vector2 = level.vector(nav_points[name])
		var ok := false
		match used[name].mode:
			"climb": ok = await climb(target)
			"jump": ok = await hop(target)
			"drop": ok = await descend(target, float(used[name].get("chute_x", NAN)))
			_: ok = await walk(target)
		if not ok:
			print("NAV FAILURE goal=%s edge=%s -> %s" % [goal, nav_at, name])
			return false
		nav_at = name
		if name in ["route_1_2", "route_20_2"]:
			await capture("west_roof" if name == "route_1_2" else "east_ruined_street")
	print("ARRIVED %s %s" % [goal, player.position])
	tour.append({"at":goal,"frame":frames,"position":[player.position.x,player.position.y]})
	return true


func hop(target: Vector2) -> bool:
	if target.y > player.position.y + 20: return await descend(target)
	release()
	for i in 60:
		if player.air_state == LanPlayer.AirState.GROUNDED: break
		await step(1)
	await step(12)
	Input.action_press(&"jump")
	var braking := false
	for i in 240:
		var dx := target.x - player.position.x
		var stop_distance := player.velocity.x * player.velocity.x / (2 * LanPlayer.AIR_ACCELERATION) + 4
		if absf(dx) < stop_distance: braking = true
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		if not braking: Input.action_press(&"ui_right" if dx > 0 else &"ui_left")
		if i == 2: Input.action_release(&"jump")
		if i > 12 and standing() and absf(player.position.y - target.y) < 5:
			release()
			return await walk_plain(target)
		if i > 40 and standing() and player.position.y < target.y - 20:
			release()
			return await descend(target)
		await step(1)
	release()
	check(false, "Normal jump stuck toward %s at %s state=%s" % [target,player.position,player.air_state])
	await capture("stuck_jump")
	return false


func descend(target: Vector2, chute_x: float = NAN) -> bool:
	release()
	var exit_x := player.position.x
	var launch_y := player.position.y
	var exit_direction := 1.0
	var downhill_direction := 0.0
	var was_grounded := false
	for i in 600:
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
		var steering_x := exit_x if grounded else target.x
		if not grounded and player.position.y >= launch_y + 24: downhill_direction = 0
		if not grounded and not is_nan(chute_x) and player.position.y < target.y - 32:
			steering_x = chute_x
		if not grounded and player.position.y < launch_y + 24:
			steering_x = player.position.x + exit_direction * 100
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


func water_journey(id: String) -> bool:
	for item in level.layout.water_itineraries[id]:
		var target := Vector2(float(item[0]), float(item[1]))
		var mode: String = item[2]
		if mode == "walk":
			if not await walk(target): return false
		elif not await swim_to(target, mode): return false
	print("WATER FINISHED %s oxygen=%.3f" % [id, level.oxygen.fraction()])
	return true


func swim_to(target: Vector2, mode: String) -> bool:
	release()
	for i in 1800:
		var offset := target - (player.position + LanSwimMotor.BODY_PROBE)
		var dx := target.x - player.position.x
		if mode == "exit":
			if absf(dx) < 20 and standing() and not player.is_in_deep_water():
				release()
				await step(12)
				return true
			if absf(dx) > 8: Input.action_press(&"ui_right" if dx > 0 else &"ui_left")
			else:
				Input.action_release(&"ui_left")
				Input.action_release(&"ui_right")
			if i % 30 < 2: Input.action_press(&"jump")
			else: Input.action_release(&"jump")
		else:
			if mode == "breathe" and absf(dx) < 22 and level.oxygen.mode == UnderwaterOxygen.Mode.BREATHING and level.oxygen.fraction() > 0.99:
				release()
				return true
			if mode != "breathe" and offset.length() < 18:
				release()
				return true
			release()
			if absf(offset.x) > 7: Input.action_press(&"ui_right" if offset.x > 0 else &"ui_left")
			if player.air_state == LanPlayer.AirState.SWIMMING:
				if absf(offset.y) > 7: Input.action_press(&"ui_up" if offset.y < 0 else &"ui_down")
			elif player.is_in_deep_water() and offset.y < 0 and i % 24 < 2:
				Input.action_press(&"jump")
		await step(1)
	release()
	check(false, "Water %s stuck toward %s at %s state=%s" % [mode,target,player.position,player.air_state])
	await capture("stuck_water")
	return false


func interact() -> void:
	release()
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await step(2)
	event.pressed = false
	Input.parse_input_event(event)
	await step(3)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	level.snap_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))


func end_test() -> void:
	release()
	var report := {"checks":checks,"failures":failures,"game_seconds":frames/60.0,"minimum_oxygen":min_oxygen,"longest_swim_seconds":longest_swim,"climb_seconds":climb_seconds,"maximum_dry_fall_px":max_dry_fall,"drowned":level.drowned_count,"tour":tour,"visited_spaces":level.visited_spaces.keys()}
	var file := FileAccess.open(output.path_join("traversal.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
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
	finish("SUNKEN CAVERN WHOLE GRAYBOX")

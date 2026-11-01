extends "../../../support/harness.gd"
## Real input/physics traversal. No warps during the measured closed-loop journey.
const SCENE := "res://scenes/levels/chapter_2_underwater/tower/underwater_tower_foundation.tscn"
const ACTIONS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"interact"]
var level: Node2D
var player: LanPlayer
var frame_count := 0
var minimum_oxygen := 1.0
var continuous_swim := 0.0
var maximum_continuous_swim := 0.0
var output := ""
var traversal_report: Dictionary = {}


func run() -> void:
	use_memory_progress()
	var assist_hud: CanvasLayer
	var assist := root.get_node_or_null("BattleAssist")
	if assist:
		for child in assist.get_children():
			if child is CanvasLayer:
				assist_hud = child
	var previous_assist_visible := assist_hud.visible if assist_hud else false
	var quest_hud: CanvasLayer
	var quest_log := root.get_node_or_null("QuestLog")
	if quest_log:
		for child in quest_log.get_children():
			if child is CanvasLayer: quest_hud = child
	var previous_quest_visible := quest_hud.visible if quest_hud else false
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/underwater_tower_foundation")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	player = level.player
	await step(40)
	check(player.position.distance_to(level.START) < 5, "Original-size Lan starts on the dry entry floor")
	check(not player.is_in_deep_water(), "Entry is a real dry chamber")
	check(not level.open_shortcut(), "Entry-side interaction cannot open the return shortcut")
	check(assist_hud == null or not assist_hud.visible, "Autoload corner helper text is suppressed only for this scene")
	check(quest_hud == null or not quest_hud.visible, "Prologue quest tracker does not leak into the tower preview")
	var helper_labels := 0
	for label in level.find_children("*", "Label", true, false):
		if not player.is_ancestor_of(label):
			helper_labels += 1
	check(helper_labels == 0, "No new map/helper labels outside the existing player HUD")
	await capture("entry")
	Input.action_press(&"ui_right")
	await step(90)
	release()
	check(player.position.x < 1280.0, "Closed gate physically blocks the entry side")
	if not await go(Vector2(1160, 3700), "walk"):
		finish(suite_name())
		return
	await journey()
	stop_test_audio()
	await wait_frames(2)
	level.queue_free()
	await wait_frames(8)
	check(assist_hud == null or assist_hud.visible == previous_assist_visible, "Scene teardown restores the previous assist HUD visibility")
	check(quest_hud == null or quest_hud.visible == previous_quest_visible, "Scene teardown restores the previous quest tracker visibility")
	expect_save_untouched()
	traversal_report["checks"] = checks
	traversal_report["failures"] = failures
	var report_file := FileAccess.open(output.path_join("traversal.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(traversal_report, "\t"))
	# Visibility restoration can play the global UI tick. Stop this test-owned
	# playback before fast headless teardown rather than exiting mid audio callback.
	stop_test_audio()
	await wait_frames(4)
	finish(suite_name())


func suite_name() -> String:
	return "UNDERWATER TOWER FOUNDATION"


func stop_test_audio() -> void:
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer2D"]:
		for voice in root.find_children("*", kind, true, false):
			voice.stop()
			voice.stream = null


func release() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func step(frames: int) -> void:
	for i in frames:
		await physics_frame
		frame_count += 1
		minimum_oxygen = minf(minimum_oxygen, level.oxygen.fraction())
		if level.oxygen.mode == UnderwaterOxygen.Mode.SWIMMING:
			continuous_swim += 1.0 / 60.0
			maximum_continuous_swim = maxf(maximum_continuous_swim, continuous_swim)
		elif level.oxygen.mode == UnderwaterOxygen.Mode.BREATHING:
			continuous_swim = 0.0


func go(target: Vector2, mode: String, timeout := 24.0) -> bool:
	release()
	await step(2)
	for frame in int(timeout * 60):
		release()
		var body := player.position + Vector2(0, -29)
		var offset := target - body
		var reached := false
		if mode == "walk":
			if absf(offset.x) > 10:
				Input.action_press(&"ui_right" if offset.x > 0 else &"ui_left")
			reached = absf(offset.x) < 22 and absf(player.position.y - target.y) < 60 and (player.is_on_floor() or player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING]) and not player.is_in_deep_water()
		elif mode == "exit":
			Input.action_press(&"ui_right" if offset.x > 0 else &"ui_left")
			if frame % 20 < 8:
				Input.action_press(&"jump")
			reached = absf(offset.x) < 48 and (player.is_on_floor() or player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING]) and not player.is_in_deep_water()
		else:
			if absf(offset.x) > 10:
				Input.action_press(&"ui_right" if offset.x > 0 else &"ui_left")
			if player.air_state != LanPlayer.AirState.SWIMMING:
				if player.is_in_deep_water() and offset.y < -10 and frame % 16 < 8:
					Input.action_press(&"jump")
				elif mode == "jump_into_water" and not player.is_in_deep_water() and frame % 30 < 8:
					Input.action_press(&"jump")
			elif absf(offset.y) > 10:
				Input.action_press(&"ui_up" if offset.y < 0 else &"ui_down")
			reached = offset.length() < 32
			if mode == "breathe":
				reached = absf(offset.x) < 35 and level.oxygen.mode == UnderwaterOxygen.Mode.BREATHING and level.oxygen.fraction() >= 0.99
		if reached:
			release()
			print("REACHED %s %s actual %s oxygen %.3f" % [mode, target, player.position, level.oxygen.fraction()])
			return true
		await step(1)
	release()
	check(false, "Traversal timeout %s %s, actual %s, air=%s oxygen=%.3f" % [mode, target, player.position, player.air_state, level.oxygen.fraction()])
	await capture("stuck")
	return false


func journey() -> void:
	var route := [
		[Vector2(830, 3550), "walk"],
		[Vector2(640, 3740), "jump_into_water"],
		[Vector2(640, 4200), "swim"],
		[Vector2(1080, 4200), "swim"],
		[Vector2(1080, 4040), "breathe"],
		[Vector2(1220, 4010), "exit"],
		[Vector2(1080, 4200), "swim"],
		[Vector2(1980, 4200), "swim"],
		[Vector2(2140, 4200), "swim"],
		[Vector2(2140, 4000), "breathe"],
		[Vector2(2330, 3970), "exit"],
		[Vector2(2140, 4200), "swim"],
		[Vector2(2600, 4200), "swim"],
		[Vector2(2600, 3200), "swim"],
		[Vector2(2600, 2940), "breathe"],
		[Vector2(2520, 2940), "breathe"],
		[Vector2(2350, 2960), "exit"],
		[Vector2(2340, 2980), "walk"],
	]
	for i in route.size():
		if not await go(route[i][0], route[i][1]):
			return
		if i in [5, 10, 16]:
			await capture("route_%02d" % i)
	if not await jump_to(Vector2(2120, 2980), &"ui_left"): return
	if not await go(Vector2(1950, 2980), "walk"): return
	await step(40)
	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	await step(4)
	interact.pressed = false
	Input.parse_input_event(interact)
	check(level.shortcut_is_open, "Real E action at the far-side latch opens S1")
	if not level.shortcut_is_open:
		return
	var before := frame_count
	if not await go(Vector2(1160, 3700), "walk", 16.0):
		return
	var return_seconds := (frame_count - before) / 60.0
	check(not player.is_in_deep_water(), "Shortcut returns to the entry using ordinary ground movement")
	check(return_seconds < 12, "Return route is short: %.2f s" % return_seconds)
	check(level.drowned_count == 0, "Full loop completes without drowning")
	check(level.camera.limit_left == 0 and level.camera.limit_right == 3328, "Camera keeps one continuous architectural span across the loop")
	check(minimum_oxygen > 0.05, "Oxygen retains a margin (min %.3f)" % minimum_oxygen)
	check(maximum_continuous_swim < 20.0, "Measured unbroken swim fits the 20 s bar: %.2f s" % maximum_continuous_swim)
	for id in [&"T01", &"T02", &"T03", &"T05", &"T04"]:
		check(id in level.visited_rooms, "Physical route visits %s" % id)
	check(await go(Vector2(2000, 2980), "walk", 18.0), "Opened stair is also traversable upward without jump or warp")
	await capture("heart_shortcut_open")
	traversal_report = {"measured_max_unbroken_swim_seconds":maximum_continuous_swim,"minimum_oxygen_fraction":minimum_oxygen,"return_seconds":return_seconds,"drowned_count":level.drowned_count,"visited":level.visited_rooms}


func jump_to(target: Vector2, direction: StringName, timeout := 150) -> bool:
	release()
	for i in 90:
		if player.air_state == LanPlayer.AirState.GROUNDED: break
		await step(1)
	Input.action_press(direction)
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	for i in timeout:
		if absf(player.position.x - target.x) < 28: Input.action_release(direction)
		await step(1)
		if absf(player.position.x - target.x) < 65 and absf(player.position.y - target.y) < 50 and player.air_state == LanPlayer.AirState.GROUNDED:
			release()
			check(true, "Ordinary jump reaches " + str(target))
			return true
	release()
	check(false, "Jump timeout at " + str(player.position) + " toward " + str(target))
	return false


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await step(12)
	level.snap_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

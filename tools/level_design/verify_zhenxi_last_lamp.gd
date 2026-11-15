extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Real-time route from the dry A18 bank through the hidden chapter and back.
## The actual boss must start from the main lamp. Only victory is injected to
## isolate the postfight route from the separate combat playtest.

const HELMET_FACT := &"zhenxi_xiaowu_helmet"
const WALK_OFFSETS := {
	"ShadowScreen": Vector2(0, 26),
	"LampInspect": Vector2(-96, 0),
}
const CITY_LAYERS := [&"FarSkyAndSmoke", &"DistantRoofline", &"MasonryAndBuildings", &"ForegroundRubble"]


func run() -> void:
	var save := use_memory_progress()
	var shadow_only := "--shadow-corridor" in OS.get_cmdline_user_args()
	var gate_only := "--gate-entry" in OS.get_cmdline_user_args()
	if "--legacy-progress" in OS.get_cmdline_user_args():
		save.try_complete_fact(&"sunken_general_defeated")
		save.try_complete_fact(&"zhenxi_last_lamp_lit")
		save.finish_cinematic(&"zhenxi_last_lamp_comic")
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		var folder := "zhenxi-shadow-corridor" if shadow_only else "zhenxi-last-lamp"
		if gate_only:
			folder = "zhenxi-gate-entry"
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/" + folder)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	player.reset_after_map_fall(level.marker("pool_bank"))
	level.snap_camera()
	await step(12)
	if shadow_only:
		await verify_shadow_corridor()
	elif gate_only:
		await verify_gate_entry(save)
	else:
		await play_route(save)
	if "--legacy-progress" in OS.get_cmdline_user_args():
		check(save.has_completed(&"zhenxi_last_lamp_lit") and save.get_cinematic_status(&"zhenxi_last_lamp_comic")
			== SaveProgressService.CinematicStatus.WATCHED, "The new route preserves the old lamp and comic facts")
	release()
	print("Route sampled at %.2fs simulated, %d drowned, minimum oxygen %.2f" % [
		frames / 60.0, level.drowned_count, min_oxygen])
	check(level.drowned_count == 0, "No drowning or hazard resets during the tour")
	var gallery_audio := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	if gallery_audio != null:
		gallery_audio.stop()
		gallery_audio.stream = null
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	var title := "ZHENXI SHADOW CORRIDOR" if shadow_only else "ZHENXI LAST LAMP ROUTE"
	finish("ZHENXI GATE ENTRY" if gate_only else title)


func play_route(save: SaveProgressService) -> void:
	var gallery := await start_fight_from_a18(save)
	if gallery == null:
		return
	print("Route-only fixture: injecting victory after proving the actual battle starts")
	gallery._on_general_defeated()
	await step(12)
	await read_story(gallery)
	await leave_after_victory(gallery, save)


func enter_chapter() -> Node2D:
	await interact()
	check(not level._inside_gallery, "A18 cannot be entered from the dry bank")
	if not await swim_to(Vector2(8960, 2880), "swim") \
			or not await swim_to(Vector2(9088, 3328), "swim") \
			or not await swim_to(Vector2(9472, 3435), "swim"):
		return null
	await interact()
	await step(35)
	check(level._inside_gallery and player == level.player, "A18 opens with E for the same Lan")
	if not level._inside_gallery:
		return null
	var music := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	check(music != null and music.playing, "The gallery starts its own music")
	return level._hidden_gallery


func verify_shadow_corridor() -> void:
	var gallery := await enter_chapter()
	if gallery == null:
		return
	var layout := gallery.get_node("ChapterLayout") as Node2D
	var shadow := gallery.get("_shadow_gallery") as Node2D
	check(shadow != null, "The authored shadow corridor is active in the real gallery")
	if shadow == null:
		return
	var front := (layout.get_node("ShadowScreen") as Marker2D).global_position.x - 30.0
	var support := (layout.get_node("ShadowPole") as Marker2D).global_position.x
	var threshold := (layout.get_node("ShadowBackThreshold") as Marker2D).global_position.x
	if not await hold_to_x(front):
		return
	await step(34)
	var front_floor := player.global_position.y
	check(shadow.reveal_amount() <= 0.03, "The curtain and facade hide the backstage from the approach")
	await interact()
	check(not gallery._shadow_restored, "E at the front cannot repair the support behind the curtain")
	check(not shadow.lamp_is_carried() and not shadow.projection_is_aligned(),
		"E at the front leaves the backstage lamp and projection unchanged")
	await capture("01_front")

	if not await hold_to_x(threshold - 20.0):
		return
	check(shadow.reveal_amount() <= 0.03, "The backstage remains hidden up to the corner")
	if not await hold_to_x(support):
		return
	await step(42)
	check(standing() and player.global_position.y >= front_floor + 50.0
		and shadow.reveal_amount() >= 0.97,
		"Holding D rounds the corner and lands in the lowered backstage with the rear revealed")
	check(not gallery._shadow_restored, "Walking past the curtain does not repair the projection")
	var centered: Vector2 = level.camera.get_screen_center_position()
	var zoom: Vector2 = level.camera.zoom
	await capture("02_rear_before_e")
	await interact()
	await step(42)
	check(gallery._shadow_restored and shadow._repair >= 0.97,
		"E near the rear support finishes the bamboo movement")
	check(not shadow.projection_is_aligned(), "The upright support still needs the lamp at the correct angle")
	check(level.camera.get_screen_center_position().distance_to(centered) <= 2.0
		and level.camera.zoom.is_equal_approx(zoom), "The before and after captures use the same camera framing")
	await capture("03_rear_after_e")

	if not await verify_shadow_lamp(layout, shadow):
		return
	check(standing(), "The regular dry route continues through the east end")
	Input.action_press(&"ui_left")
	await step(8)
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	await step(8)
	Input.action_press(&"instant_dash")
	await step(3)
	Input.action_release(&"instant_dash")
	check(player.aerial_dash_used, "Lan can jump and air-dash while turning back through the corridor")
	if not await hold_to_x(front):
		return
	await step(42)
	check(standing() and shadow.reveal_amount() <= 0.03,
		"Backtracking restores the curtain-side composition after an aerial approach")
	check(gallery._shadow_restored and shadow.projection_is_aligned() and not shadow.lamp_is_carried(),
		"Returning to the front retains the aligned projection and the seated lamp")
	await capture("04_front_return")
	check(not is_instance_valid(gallery.general) and not player.input_frozen,
		"The optional corridor interaction leaves normal movement active")


func verify_shadow_lamp(layout: Node2D, shadow: Node2D) -> bool:
	var source: float = (layout.get_node("ShadowWorkLamp") as Marker2D).global_position.x
	var rest: float = (layout.get_node("ShadowLampRest") as Marker2D).global_position.x
	if not await hold_to_x(source):
		return false
	var floor_y := player.global_position.y
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	await step(11)
	await interact()
	check(player.global_position.y < floor_y - 35.0 and not shadow.lamp_is_carried(),
		"An airborne E over the lamp leaves it on its holder")
	await step(52)

	await interact()
	check(shadow.lamp_is_carried(), "A grounded E near the lamp lifts it from the original holder")
	if not await hold_to_x((source + rest) * 0.5):
		return false
	await step(24)
	check(shadow.lamp_is_carried() and not shadow.projection_is_aligned(),
		"Carrying the lamp partway leaves the repaired soldier out of line")
	await capture("05_lamp_midway")
	if not await hold_to_x(source):
		return false
	await interact()
	check(not shadow.lamp_is_carried() and not shadow.projection_is_aligned(),
		"Returning the lamp to its original holder leaves the projection misaligned")
	await interact()
	check(shadow.lamp_is_carried(), "The lamp can be lifted again after returning it")
	if not await hold_to_x(rest):
		return false
	await step(24)
	check(shadow.lamp_is_carried() and shadow.projection_is_aligned(),
		"The carried light aligns the restored soldier at the second holder")
	await capture("06_lamp_aligned_in_hand")
	await interact()
	await step(24)
	check(not shadow.lamp_is_carried() and shadow.projection_is_aligned(),
		"Placing the lamp on the second holder keeps the soldier in formation")
	await capture("07_lamp_seated")
	await interact()
	check(shadow.lamp_is_carried(), "The second holder also allows picking up the lamp")
	if not await hold_to_x(layout.to_global(Vector2(7210, 0)).x):
		return false
	await step(24)
	check(not shadow.lamp_is_carried() and shadow.projection_is_aligned(),
		"Leaving the work area returns the lamp to its last holder")
	return true


func hold_to_x(target: float) -> bool:
	var direction := signf(target - player.global_position.x)
	if is_zero_approx(direction):
		return true
	var action := &"ui_right" if direction > 0.0 else &"ui_left"
	Input.action_press(action)
	var reached := false
	var timeout := ceili(absf(target - player.global_position.x) / 120.0 * 60.0) + 180
	for frame in timeout:
		if direction * (target - player.global_position.x) <= 4.0:
			reached = true
			break
		await step(1)
	release()
	await step(4)
	check(reached, "Holding the movement direction reaches corridor x %.0f at %s"
		% [target, player.global_position])
	return reached


func start_fight_from_a18(save: SaveProgressService) -> Node2D:
	var gallery := await enter_chapter()
	if gallery == null:
		return null
	var layout := gallery.get_node_or_null("ChapterLayout") as Node2D
	check(layout != null, "Production route enters the new chapter layout")
	if layout == null:
		return null
	await capture("01_arrival")
	if not await walk_to_mark(layout, "XiaowuEntrance"):
		return null
	await interact()
	check(await read_story(gallery), "E opens Xiaowu's dialogue")
	await capture("02_water_gate")
	var capture_city := "--city-visual" in OS.get_cmdline_user_args()
	if capture_city and not await capture_city_walk(layout, [5900.0, 6140.0, 6420.0]):
		return null
	if not await walk_to_mark(layout, "ShadowScreen") or not await walk_to_mark(layout, "ShadowPole"):
		return null
	await interact()
	await read_story(gallery)
	check(gallery._shadow_restored, "E at the shadow pole projects the soldier formation")
	await capture("03_shadow_corridor")
	if capture_city and not await capture_city_walk(layout, [7030.0, 7300.0, 7520.0, 7750.0]):
		return null
	if not await walk_to_mark(layout, "LampInspect"):
		return null
	check(not is_instance_valid(gallery.general), "Approaching the lamp does not skip the encounter dialogue")
	check(not save.has_completed(gallery.CHAPTER_VICTORY), "Approaching the lamp does not write the new victory")
	check(not gallery._chapter_layout._return_open, "The return passage is shut before combat")
	await capture("04_lamp_approach")
	if not await interact_at_lamp(gallery, true, "--auto-lamp" in OS.get_cmdline_user_args()):
		return null
	check(gallery.general.combat_target == player and not gallery.general.manual_control,
		"The boss is the normal encounter targeting Lan")
	check(level.camera.limit_right - level.camera.limit_left == 1280,
		"The first two phases contain one viewport")
	await capture("05_battle_start")
	return gallery


func capture_city_walk(layout: Node2D, sampling_points: Array[float]) -> bool:
	var samples: Array[Dictionary] = []
	var trace := Callable()
	if "--city-parallax" in OS.get_cmdline_user_args():
		var city := layout.get_parent().get_node_or_null("RuinedCityArt")
		var layers: Array[Node2D] = []
		for layer_name: StringName in CITY_LAYERS:
			var layer := city.get_node_or_null(NodePath(layer_name)) as Node2D if city != null else null
			if not is_instance_valid(layer):
				check(false, "Live parallax layer exists: " + String(layer_name))
				return false
			layers.append(layer)
		trace = sample_city_layers.bind(layout, layers, samples)
		physics_frame.connect(trace)
	var reached := true
	for x: float in sampling_points:
		var floor := Vector2(x, float(layout.upper_floor_y(x)))
		if not await walk_plain(level.to_local(layout.to_global(floor))):
			reached = false
			break
		await step(24)
		await capture("walk_%04d" % int(x))
	if trace.is_valid():
		physics_frame.disconnect(trace)
		write_city_motion(sampling_points, samples)
	return reached


func sample_city_layers(layout: Node2D, layers: Array[Node2D], samples: Array[Dictionary]) -> void:
	var screen_x: Array[float] = []
	for layer in layers:
		screen_x.append(layer.get_global_transform_with_canvas().origin.x)
	samples.append({
		"physics_frame": Engine.get_physics_frames(),
		"time_us": Time.get_ticks_usec(),
		"player_x": layout.to_local(player.global_position).x,
		"camera_x": layout.to_local(level.camera.get_screen_center_position()).x,
		"screen_x": screen_x,
	})


func write_city_motion(points: Array[float], samples: Array[Dictionary]) -> void:
	var first: Dictionary = samples.front()
	var last: Dictionary = samples.back()
	var travel := float(last.camera_x) - float(first.camera_x)
	var layer_travel: Array[float] = []
	for i in CITY_LAYERS.size():
		layer_travel.append(float(first.screen_x[i]) - float(last.screen_x[i]))
	check(travel > 100.0 and layer_travel[0] < layer_travel[1] and layer_travel[1] < layer_travel[2]
		and layer_travel[2] + 5.0 < layer_travel[3],
		"Gameplay camera pans through four distinct depth speeds: %s" % [layer_travel])
	DirAccess.make_dir_recursive_absolute(output)
	var filename := "motion_%04d_to_%04d.json" % [int(points.front()), int(points.back())]
	var artifact := FileAccess.open(output.path_join(filename), FileAccess.WRITE)
	if artifact == null:
		check(false, "The motion trace can be written: " + filename)
		return
	artifact.store_string(JSON.stringify({
		"layer_order": CITY_LAYERS,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"camera_travel": travel,
		"layer_travel": layer_travel,
		"samples": samples,
	}, "\t"))
	artifact.close()


func interact_at_lamp(gallery: Node2D, expect_dialogue: bool, approach := false) -> bool:
	var samples: Array[Dictionary] = []
	var trace := Callable()
	if "--gate-entry" in OS.get_cmdline_user_args():
		var music := level.get_node("ZhenxiGateMusic") as AudioStreamPlayer
		trace = sample_gate_entry.bind(gallery, music, samples)
		trace.call()
		process_frame.connect(trace)
	if approach:
		Input.action_press(&"ui_right")
		for frame in 90:
			if player.input_frozen:
				break
			await step(1)
		release()
	else:
		await interact()
	var saw_dialogue := await read_story(gallery)
	check(saw_dialogue == expect_dialogue, "The first lamp interaction gives the dialogue, then retries skip it")
	for attempt in 120:
		if is_instance_valid(gallery.general):
			break
		await step(1)
	check(is_instance_valid(gallery.general), "Finishing the lamp dialogue starts the production boss")
	if trace.is_valid():
		await step(8)
		process_frame.disconnect(trace)
		check_gate_entry_trace(samples, "first" if expect_dialogue else "retry")
	return is_instance_valid(gallery.general)


func verify_gate_entry(save: SaveProgressService) -> void:
	var gallery := await start_fight_from_a18(save)
	if gallery == null:
		return
	level._retry_hidden_battle()
	await step(8)
	var layout := gallery.get_node("ChapterLayout") as Node2D
	if await walk_to_mark(layout, "LampInspect") and await interact_at_lamp(gallery, false):
		await capture("06_retry_battle_start")


func sample_gate_entry(gallery: Node2D, music: AudioStreamPlayer, samples: Array[Dictionary]) -> void:
	var center: Vector2 = level.camera.get_screen_center_position()
	samples.append({
		"time_us": Time.get_ticks_usec(),
		"camera_x": center.x,
		"camera_y": center.y,
		"pending": gallery._entry_pending,
		"input_frozen": player.input_frozen,
		"boss_exists": is_instance_valid(gallery.general),
		"music_playing": music.playing and not music.stream_paused,
		"music_position": music.get_playback_position(),
	})


func check_gate_entry_trace(samples: Array[Dictionary], label: String) -> void:
	var lead_in_frames := 0
	var blocked_input_only := true
	var music_continuous := true
	var largest_step := 0.0
	var previous := Vector2(float(samples[0].camera_x), float(samples[0].camera_y))
	var previous_audio := float(samples[0].music_position)
	for frame in samples:
		var center := Vector2(float(frame.camera_x), float(frame.camera_y))
		if frame.pending:
			lead_in_frames += 1
			blocked_input_only = blocked_input_only and frame.input_frozen and not frame.boss_exists
		if lead_in_frames > 0:
			largest_step = maxf(largest_step, previous.distance_to(center))
		var audio := float(frame.music_position)
		music_continuous = music_continuous and frame.music_playing and audio >= previous_audio - 0.05
		previous = center
		previous_audio = audio
	check(lead_in_frames > 0 and blocked_input_only and samples.back().boss_exists and not samples.back().input_frozen,
		"%s entrance frames the arena before it creates a live boss and restores movement" % label)
	check(largest_step < 8.0, "%s entrance largest camera step %.3f px" % [label, largest_step])
	var native_realtime := DisplayServer.get_name() != "headless" and not "--fixed-fps" in OS.get_cmdline_args()
	check(music_continuous and (not native_realtime or previous_audio - float(samples[0].music_position) > 0.2),
		"%s entrance keeps the current music playing without restarting" % label)
	DirAccess.make_dir_recursive_absolute(output)
	var artifact := FileAccess.open(output.path_join("gate_entry_%s.json" % label), FileAccess.WRITE)
	if artifact != null:
		artifact.store_string(JSON.stringify({"largest_step": largest_step, "lead_in_frames": lead_in_frames, "samples": samples}, "\t"))


func leave_after_victory(gallery: Node2D, save: SaveProgressService) -> void:
	check(gallery.won and save.has_completed(gallery.VICTORY) and save.has_completed(gallery.CHAPTER_VICTORY)
		and not is_instance_valid(gallery.general),
		"Victory releases the battlefield and is saved independently")
	var layout := gallery.get_node("ChapterLayout") as Node2D
	var return_entry := layout.get_node("ReturnEntry") as Marker2D
	var music := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	check(not save.has_claimed_reward(HELMET_FACT), "Winning alone does not collect Xiaowu's helmet")
	if not await walk_to_mark(layout, "StoryHelmet"):
		return
	await interact()
	await read_story(gallery)
	check(save.has_claimed_reward(HELMET_FACT) and save.get_item_count(HELMET_FACT) == 1,
		"E at the helmet adds the named unique inventory item")
	await interact()
	await read_story(gallery)
	check(save.get_item_count(HELMET_FACT) == 1, "The helmet reward cannot be collected twice")
	await capture("06_helmet")
	if not await enter_return_passage(return_entry, gallery) or not await walk_to_mark(layout, "Archive"):
		return
	check(player.position.y - gallery.position.y > 750, "The return leads through the lower passage")
	await capture("07_archive")
	await interact()
	check(await read_story(gallery), "The optional archive can be read from the lower passage")
	if not await walk_to_mark(layout, "ReturnJoin") or not await walk_to_mark(layout, "ReturnDoor"):
		return
	check(not is_instance_valid(gallery.general), "Walking back does not restart the fight")
	await interact()
	await step(35)
	check(not level._inside_gallery and player.is_in_deep_water(), "The original arch returns to A18 underwater")
	if level._inside_gallery:
		return
	check(music == null or not music.playing, "The gallery track releases when Lan leaves")
	if not await swim_to(Vector2(9088, 3328), "swim") or not await swim_to(Vector2(8880, 2880), "swim"):
		return
	check(await swim_to(level.marker("pool_bank"), "exit"), "Lan can swim back to the A18 dry bank")
	await capture("08_returned_to_a18")


func walk_to_mark(layout: Node2D, name: String) -> bool:
	var marker := layout.get_node_or_null(NodePath(name)) as Marker2D
	check(marker != null, "Route marker exists: " + name)
	if marker == null:
		return false
	var destination := level.to_local(marker.global_position) + (WALK_OFFSETS.get(name, Vector2.ZERO) as Vector2)
	var reached := await walk_plain(destination)
	check(reached, "Real Lan traverses to %s at %s" % [name, destination])
	return reached


func enter_return_passage(entry: Marker2D, gallery: Node2D) -> bool:
	var drop_edge := entry.global_position.x
	Input.action_press(&"ui_right")
	for frame in 360:
		if player.global_position.x >= drop_edge:
			break
		await step(1)
	release()
	await step(55)
	var landed := standing() and player.global_position.y - gallery.global_position.y > 750.0
	check(landed, "The east exit opens a physical descent into the return passage")
	return landed


func interact() -> void:
	release()
	await tap_key(KEY_E)
	await step(3)


func tap_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await step(2)
	var lift := InputEventKey.new()
	lift.physical_keycode = key
	lift.keycode = key
	Input.parse_input_event(lift)


func read_story(gallery: Node2D) -> bool:
	var saw_story := false
	for beat in 24:
		var active := false
		for child in gallery.find_children("*", "CanvasLayer", true, false):
			if child is TutorialDialogue and child.opened:
				active = true
			elif child is ComicPlayer and child.visible:
				active = true
		if not active and not player.input_frozen:
			break
		saw_story = saw_story or active
		await tap_key(KEY_SPACE)
		await step(20)
	return saw_story


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

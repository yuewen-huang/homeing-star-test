extends "../../tests/support/harness.gd"
## Standalone route from the flooded entrance to the lamp court and back.
## The actual boss must start from the main lamp. Only victory is injected to
## isolate the postfight route from the separate combat playtest.

const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
const ACTIONS := [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"interact"]
var level: Node2D
var player: LanPlayer
var frames := 0
var min_oxygen := 1.0
var output := ""

const HELMET_FACT := &"zhenxi_xiaowu_helmet"
const SLUICE_PREVIEW := preload("preview_zhenxi_sluice.gd")
const CAVERN_PREVIEW := preload("preview_sunken_cavern.gd")
const WALK_OFFSETS := {
	"GrainSacks": Vector2(50, 0),
	"ReturnDoor": Vector2(-22, 0),
	"LampInspect": Vector2(-96, 0),
}
const CITY_LAYERS := [&"FarSkyAndSmoke", &"DistantRoofline", &"MasonryAndBuildings", &"ForegroundRubble"]


func run() -> void:
	var save := use_memory_progress()
	var shadow_only := "--shadow-corridor" in OS.get_cmdline_user_args()
	var gate_only := "--gate-entry" in OS.get_cmdline_user_args()
	var aftermath_only := "--aftermath-only" in OS.get_cmdline_user_args()
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
	level.snap_camera()
	await step(12)
	if shadow_only:
		await verify_shadow_corridor()
	elif gate_only:
		await verify_gate_entry(save)
	elif aftermath_only:
		await CAVERN_PREVIEW.stage_court(level)
		var gallery: Node2D = level._hidden_gallery
		gallery._on_general_defeated()
		gallery.place_at_victory_return()
		level.snap_camera()
		await step(12)
		await leave_after_victory(gallery, save)
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
	var gallery := await start_chapter_fight(save)
	if gallery == null:
		return
	print("Route-only fixture: injecting victory after proving the actual battle starts")
	gallery._on_general_defeated()
	await step(12)
	await read_story(gallery)
	await leave_after_victory(gallery, save)


func enter_chapter() -> Node2D:
	await level._cross_hidden_door()
	var music := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	check(music != null and music.playing, "The gallery starts its own music")
	if is_instance_valid(level.sluice) and not await cross_sluice(level.sluice):
		return null
	return level._hidden_gallery


func verify_shadow_corridor() -> void:
	var gallery := await enter_chapter()
	check(gallery != null, "The real shadow route reaches the existing lamp court")


func cross_sluice(section: ZhenxiSluiceSection) -> bool:
	var controller := SLUICE_PREVIEW.RouteInput.new(self)
	if not await controller.leave_pool(section) or not await controller.board_from_entry(section):
		check(false, "Lan swims ashore and boards on her own")
		return false
	await capture("01_approach_board")
	var aligned := await controller.position_for_jump(section, 490.0, true)
	check(aligned and section.shadow_wall.shadow_on_cloth, "The actual moving plate carries Lan through the projected formation")
	if not aligned:
		return false
	await capture("02_shadow_on_cloth")
	await controller.jump_right(115)
	if not section.reached_exit or not await controller.climb_rear_steps(section):
		check(false, "Lan jumps through the throat and climbs the rear steps")
		return false
	check(section.shadow_wall.rear_view == 1.0, "The rear steps reveal the bamboo and armor behind the same cloth")
	await capture("03_behind_the_cloth")
	await controller.walk_right(section, ZhenxiSluiceSection.COMIC_THRESHOLD, 130)
	await resolve_passage(level.ARRIVAL_COMIC_ID)
	check(level.sluice == null, "Clearing the rear threshold lands Lan in the existing court")
	return level.sluice == null


func resolve_passage(id: StringName) -> void:
	await step(3)
	for frame in 180:
		var comic: WindSightingComic = level._passage_comic
		if comic != null and not comic.get("covered_by_fade"):
			check(comic.cinematic_id == id, "The route opens the passage comic in sequence")
			await tap_key(KEY_ESCAPE)
			break
		if not level._crossing_door:
			break
		await step(1)
	await step(32)


func start_chapter_fight(save: SaveProgressService) -> Node2D:
	var gallery := await enter_chapter()
	if gallery == null:
		return null
	var layout := gallery.get_node_or_null("ChapterLayout") as Node2D
	check(layout != null, "Production route enters the new chapter layout")
	if layout == null:
		return null
	await capture("01_arrival")
	if "--decoy-sacks" in OS.get_cmdline_user_args():
		if not await walk_to_mark(layout, "GrainSacks"):
			return null
		await verify_decoy_sacks(gallery, save)
	if "--city-visual" in OS.get_cmdline_user_args() and not await capture_city_walk(layout, [8250.0, 8690.0, 9120.0]):
		return null
	if not await walk_to_mark(layout, "LampInspect"):
		return null
	check(not is_instance_valid(gallery.general), "Approaching the lamp does not skip the encounter dialogue")
	check(not save.has_completed(gallery.CHAPTER_VICTORY), "Approaching the lamp does not write the new victory")
	check(not gallery._chapter_layout._gate_barrier.disabled, "The main gate is shut before combat")
	await capture("04_lamp_approach")
	if not await interact_at_lamp(gallery, true, "--auto-lamp" in OS.get_cmdline_user_args()):
		return null
	check(gallery.general.combat_target == player and not gallery.general.manual_control,
		"The boss is the normal encounter targeting Lan")
	check(level.camera.limit_right - level.camera.limit_left == 1280,
		"The first two phases contain one viewport")
	await capture("05_battle_start")
	return gallery


func verify_decoy_sacks(gallery: Node2D, save: SaveProgressService) -> void:
	var sacks := gallery._props.get_node("DecoySacks") as DamageReceiver2D
	check(not sacks.split and not save.has_completed(sacks.SPLIT), "The decoy sacks start intact")
	Input.action_press(&"ui_left")
	await step(2)
	release()
	await tap_key(KEY_J)
	await step(32)
	check(sacks.split and save.has_completed(sacks.SPLIT),
		"Lan's real J attack tears open the sacks and records the optional discovery")
	await capture("02_decoy_sacks_split")


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
		and is_equal_approx(layer_travel[2], layer_travel[3]),
		"Distant layers move at different speeds and foreground rubble stays anchored to the street: %s" % [layer_travel])
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
			if gallery._near_marker(^"LampInspect", 45.0):
				break
			await step(1)
		release()
		await step(5)
		check(not player.input_frozen and not is_instance_valid(gallery.general),
			"Walking up to the lamp keeps Lan in control until she interacts")
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
	var gallery := await start_chapter_fight(save)
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
	var music := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	var view := gallery.get_node("PostBattleView") as CanvasLayer
	check(not save.has_claimed_reward(HELMET_FACT), "Winning alone does not collect Xiaowu's helmet")
	check(not save.has_completed(gallery.ARCHIVE_READ), "Victory does not mark the optional archive read")
	await capture("06_lamp_return")
	if "--upper-return" in OS.get_cmdline_user_args():
		check(not save.has_claimed_reward(HELMET_FACT) and not save.has_completed(gallery.ARCHIVE_READ),
			"The departure does not require collecting the helmet or reading the archive")
	elif not await inspect_aftermath(gallery, save, layout, view, music):
		return
	if not await walk_to_mark(layout, "ReturnDoor"):
		return
	check(not is_instance_valid(gallery.general), "Walking back does not restart the fight")
	await interact()
	await resolve_passage(level.DEPARTURE_COMIC_ID)
	var bank: Vector2 = level.start
	check(not level._inside_gallery and not player.is_in_deep_water() and player.position.distance_to(bank) < 24.0,
		"The main gate returns to the quay")
	if level._inside_gallery:
		return
	check(music == null or not music.playing, "The gallery track releases when Lan leaves")
	await capture("08_returned_to_a18")


func inspect_aftermath(gallery: Node2D, save: SaveProgressService, layout: Node2D,
		view: CanvasLayer, music: AudioStreamPlayer) -> bool:
	if not await walk_to_mark(layout, "StoryHelmet"):
		return false
	await interact()
	check(view.visible and player.input_frozen, "E opens the helmet inspection and locks movement")
	check(save.has_claimed_reward(HELMET_FACT) and save.get_item_count(HELMET_FACT) == 1,
		"E at the helmet adds the named unique inventory item")
	await capture("06_helmet_detail")
	await interact()
	await interact()
	check(not view.visible and save.get_item_count(HELMET_FACT) == 1,
		"The inspection closes and the helmet cannot be collected twice")
	if not await walk_to_mark(layout, "Archive"):
		return false
	await capture("07_archive_niche")
	var reading_position := player.global_position
	var track: AudioStream = music.stream if music else null
	await interact()
	check(view.visible and view.archive_page == 0 and player.input_frozen
		and not save.has_completed(gallery.ARCHIVE_READ), "Opening the archive displays page one without recording a read")
	await capture("07_archive_page_one")
	await tap_key(KEY_ESCAPE)
	check(not view.visible and not player.input_frozen and not save.has_completed(gallery.ARCHIVE_READ),
		"Esc on page one restores movement and leaves the archive unread")
	await interact()
	await interact()
	check(view.visible and view.archive_page == 1 and save.has_completed(gallery.ARCHIVE_READ),
		"Reopening and using E to reach page two records the archive")
	await capture("07_archive_page_two")
	await interact()
	check(not view.visible and not player.input_frozen and reading_position.distance_to(player.global_position) < 8,
		"E on page two closes the archive with Lan at the niche")
	if DisplayServer.get_name() != "headless":
		check(music != null and music.playing and not music.stream_paused and music.stream == track,
			"Reading the archive leaves the gallery track playing")
	return true


func walk_to_mark(layout: Node2D, name: String) -> bool:
	var marker := layout.get_node_or_null(NodePath(name)) as Marker2D
	check(marker != null, "Route marker exists: " + name)
	if marker == null:
		return false
	var destination := level.to_local(marker.global_position) + (WALK_OFFSETS.get(name, Vector2.ZERO) as Vector2)
	var reached := await walk_plain(destination)
	check(reached, "Real Lan traverses to %s at %s" % [name, destination])
	return reached


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


func step(count: int) -> void:
	for i in count:
		await physics_frame
		frames += 1
		min_oxygen = minf(min_oxygen, level.oxygen.fraction())

func standing() -> bool:
	return player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING]

func release() -> void:
	for action in ACTIONS: Input.action_release(action)

func walk_plain(target: Vector2) -> bool:
	release()
	var seconds := absf(player.position.x - target.x) / 150.0 + 5
	for i in int(seconds * 60):
		var dx := target.x - player.position.x
		if absf(dx) < 9 and absf(player.position.y - target.y) < 9 and standing():
			release()
			await step(4)
			return true
		if absf(dx) > 5: Input.action_press(&"ui_right" if dx > 0 else &"ui_left")
		else:
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
		await step(1)
	release()
	check(false, "Walk stuck toward %s at %s state=%s" % [target, player.position, player.air_state])
	await capture("stuck_walk")
	return false

func end_test() -> void:
	release()
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("ZHENXI CHAPTER")

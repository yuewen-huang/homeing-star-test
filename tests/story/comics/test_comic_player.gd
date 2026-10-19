extends SceneTree

class Probe extends ComicPlayer:
	var attempts := 0
	var commit_ok := true
	var last_skipped := false
	func _get_panels() -> Array[Texture2D]:
		var pixels := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.SEA_GREEN)
		var texture := ImageTexture.create_from_image(pixels)
		return [texture, ComicPlayer.atlas_panel(texture, Rect2(4, 4, 20, 16)), texture]
	func _on_playback_finished(skipped: bool) -> bool:
		attempts += 1
		last_skipped = skipped
		if not commit_ok: _hint.text = "保存失败，请重试"
		return commit_ok

class MemorySave extends SaveProgressService:
	var fail_write := false
	func _ready() -> void: pass
	func save_progress() -> bool: return not fail_write

class MemoryTransition extends SceneTransitionService:
	var destinations: Array[String] = []
	var music_arguments: Array[AudioStream] = []
	func _ready() -> void: pass
	func transition_to(path: String, music: AudioStream = null) -> void:
		destinations.append(path)
		music_arguments.append(music)

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func press(code: Key = KEY_E, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.echo = false
	event.pressed = false
	root.push_input(event)

func run() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var probe := Probe.new()
	var finished: Array[bool] = []
	probe.playback_finished.connect(func(skipped: bool): finished.append(skipped))
	root.add_child(probe)
	check(probe.panel_index == 0 and probe._image.texture == probe._frames[0], "Independent texture begins at frame zero")
	check(probe.layer == 900 and probe._image.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "Shared view retains HUD coverage and smooth filtering")
	press(KEY_E, true)
	press(KEY_A)
	# Do not send an unconfigured Esc to the global settings-menu handler.
	var unconfigured_skip := InputEventKey.new()
	unconfigured_skip.physical_keycode = KEY_ESCAPE
	unconfigured_skip.pressed = true
	probe._input(unconfigured_skip)
	check(probe.panel_index == 0 and probe.attempts == 0, "Echo, unrelated input and unconfigured skip do nothing")
	transition.is_transitioning = true
	press()
	check(probe.panel_index == 0, "Incoming scene fade locks advancement")
	transition.is_transitioning = false
	press(KEY_SPACE)
	check(probe.panel_index == 1 and probe._image.texture is AtlasTexture, "Atlas and independent textures share one player")
	press(KEY_ENTER)
	check(probe.panel_index == 1, "Rapid input cannot skip panel fade")
	await create_timer(0.3).timeout
	press(KEY_ENTER)
	await create_timer(0.3).timeout
	probe.commit_ok = false
	press()
	check(not probe._finished and finished.is_empty() and probe.attempts == 1, "Failed completion stays retryable without success event")
	check(probe._hint.text.contains("保存失败"), "Failed completion retains caller error hint")
	probe.commit_ok = true
	press()
	press()
	check(probe._finished and probe.attempts == 2 and finished == [false], "Retry succeeds once; repeated final input cannot reenter")
	probe.free()

	probe = Probe.new()
	probe.allow_skip = true
	probe.commit_ok = false
	root.add_child(probe)
	transition.is_transitioning = true
	press(KEY_ESCAPE)
	check(probe.attempts == 0, "Incoming scene fade also locks skip")
	transition.is_transitioning = false
	press(KEY_ESCAPE)
	check(probe.attempts == 1 and probe.last_skipped and not probe._finished, "Failed skip can be retried without converting to watched")
	probe.commit_ok = true
	press(KEY_ESCAPE)
	check(probe._finished and probe.last_skipped and probe.attempts == 2, "Explicit skip retries and finishes correctly")
	probe.free()

	probe = Probe.new()
	probe.initial_panel = 1
	probe.auto_hold_duration = 1.0
	probe.auto_hint = "短播"
	root.add_child(probe)
	probe.set_process(false)
	transition.is_transitioning = true
	probe._process(10.0)
	check(probe.panel_index == 1 and probe._auto_remaining == 1.0, "Short-play begins on selected frame and waits through scene fade")
	transition.is_transitioning = false
	press()
	check(probe.panel_index == 1, "Manual input cannot reveal other frames during short-play")
	probe._process(0.75)
	check(probe.attempts == 0, "Short-play holds full duration after scene fade")
	probe.commit_ok = false
	probe._process(0.3)
	probe._process(10.0)
	check(probe.attempts == 1 and probe.auto_hold_duration < 0.0, "Failed automatic completion stops retry loop and permits explicit retry")
	probe.commit_ok = true
	press()
	check(probe._finished and probe.attempts == 2, "Short-play failure can be retried manually")
	probe.free()

	probe = Probe.new()
	probe.auto_hold_duration = 0.1
	var stale_completion := [0]
	probe.playback_finished.connect(func(_skipped: bool): stale_completion[0] += 1)
	root.add_child(probe)
	probe.free()
	await create_timer(0.2).timeout
	check(stale_completion[0] == 0, "Freed short-play never invokes a delayed completion")

	# Test scene-specific save/transition policies without touching disk or loading maps.
	var original_save := root.get_node("SaveProgress") as SaveProgressService
	root.remove_child(original_save)
	root.remove_child(transition)
	var save := MemorySave.new()
	save.name = "SaveProgress"
	save._loaded = true
	root.add_child(save)
	var routing := MemoryTransition.new()
	routing.name = "SceneTransition"
	root.add_child(routing)
	for name in ["back_alley_entry", "back_alley_pill", "navigation_hall_entry", "navigation_hall_exit"]:
		save._config = ConfigFile.new()
		var comic = load("res://scenes/story/comics/%s_comic.tscn" % name).instantiate()
		root.add_child(comic)
		comic._show_panel(comic.PANELS.size() - 1, false)
		var before := routing.destinations.size()
		press()
		press()
		check(routing.destinations.size() == before + 1, name + " final panel routes exactly once")
		check(routing.music_arguments[-1] == null, name + " preserves existing BGM")
		if name == "back_alley_entry":
			check(save.has_completed(SaveProgressService.STORY_BACK_ALLEY_ENTERED), "Back alley entry retains existing story mark")
		elif name == "back_alley_pill":
			check(save.has_completed(SaveProgressService.QUEST_BACK_ALLEY_STEP) and routing.town_return_x == 350.0, "Pill comic retains quest mark and return position")
		elif name == "navigation_hall_exit":
			check(save.has_completed(SaveProgressService.QUEST_LAN_AND_WIND_STEP), "Hall exit retains existing comic mark")
		comic.free()

	for data: Array in [
		["back_alley_entry", SaveProgressService.STORY_BACK_ALLEY_ENTERED, 2],
		["back_alley_entry", SaveProgressService.QUEST_BACK_ALLEY_STEP, 2],
		["navigation_hall_entry", SaveProgressService.QUEST_FIRST_SIGHT_STEP, 3],
		["navigation_hall_exit", SaveProgressService.STORY_LAN_AND_WIND_TALK, 0],
		["navigation_hall_exit", SaveProgressService.QUEST_LAN_AND_WIND_STEP, 0],
	]:
		save._config = ConfigFile.new()
		save._config.set_value("progress", String(data[1]), true)
		var revisit = load("res://scenes/story/comics/%s_comic.tscn" % data[0]).instantiate()
		root.add_child(revisit)
		revisit.set_process(false)
		check(revisit.panel_index == data[2] and revisit.auto_hold_duration == 1.0, String(data[0]) + " retains selected short-play frame")
		var before := routing.destinations.size()
		routing.is_transitioning = true
		revisit._process(10.0)
		check(routing.destinations.size() == before, "Short-play waits for incoming scene fade")
		routing.is_transitioning = false
		revisit._process(0.99)
		check(routing.destinations.size() == before, "Short-play keeps the full one-second hold")
		revisit._process(0.02)
		check(routing.destinations.size() == before + 1, "Short-play routes once after hold")
		revisit.free()

	save._config = ConfigFile.new()
	save.fail_write = true
	var forest = load("res://scenes/story/comics/forest_entry_comic.tscn").instantiate()
	root.add_child(forest)
	forest._show_panel(5, false)
	var routes := routing.destinations.size()
	press()
	check(not forest._finished and routing.destinations.size() == routes, "Forest save failure blocks scene change")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_FOREST_ENTRY) == SaveProgressService.CinematicStatus.UNHANDLED, "Forest save failure rolls back watched record")
	save.fail_write = false
	press()
	check(routing.destinations.size() == routes + 1 and routing.music_arguments[-1] == Chapter1Music.FOREST, "Forest retry commits before designated forest music change")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_FOREST_ENTRY) == SaveProgressService.CinematicStatus.WATCHED, "Forest retry writes independent watched status")
	forest.free()

	var card := AberrationMasterCutIn.new()
	var card_finished := [0]
	card.finished.connect(func(): card_finished[0] += 1)
	root.add_child(card)
	press()
	check(not card.input_enabled and card_finished[0] == 0, "Sword card ignores input until authored swoop settles")
	await create_timer(0.3).timeout
	check(card.input_enabled and card.layer == 14 and card._hint.visible, "Sword card keeps authored low layer and ready prompt")
	check(card._image.position.is_equal_approx(card.FINAL_POSITION) and not card.full_screen, "Sword card keeps authored placement without full-screen background")
	check(card._hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and card._hint.get_theme_font_size("font_size") == 18 \
		and card._hint.offset_top == -40.0 and card._hint.offset_bottom == -8.0,
		"Sword card shares the same bottom hint style as full-screen comics")
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join("common_comic_sword_card.png")) == OK, "Capture shared sword-card presentation")
	press()
	press()
	await process_frame
	check(card_finished[0] == 1 and not is_instance_valid(card), "Sword card shares finish guard and releases after one completion")
	save.free()
	routing.free()
	root.add_child(original_save)
	root.add_child(transition)
	print("COMIC PLAYER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

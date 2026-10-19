extends SceneTree

const TOWN := "res://scenes/levels/town/homeward_town.tscn"
const COMIC := "res://scenes/story/comics/forest_entry_comic.tscn"
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
var save: SaveProgressService
var transition: SceneTransitionService
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func _seed_progress(entered: bool = false) -> void:
	var config := ConfigFile.new()
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			config.set_value("progress", String(value), not String(value).begins_with("story_c1_"))
	config.set_value("progress", String(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), true)
	config.set_value("progress", String(SaveProgressService.STORY_C1_FOREST_ENTERED), entered)
	save._config = config
	save._loaded = true
	save.progress_changed.emit()

func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null

func enter(path: String) -> Node:
	clear_scene()
	var room: Node = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	return room

func press(code: Key = KEY_E, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.echo = false
	event.pressed = false
	root.push_input(event)

func click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func at_gate() -> Node:
	var town = await enter(TOWN)
	town.player.position = town.right_gate_hint_anchor.position + Vector2(0, 42)
	await process_frame
	check(town.right_gate_hint.can_interact(), "Town gate remains available")
	return town

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	transition = root.get_node("SceneTransition") as SceneTransitionService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	_seed_progress()
	var comic = await enter(COMIC)
	check(comic.panel_index == 0 and not comic._revisit, "First visit starts at farewell")
	check(comic is ComicPlayer and comic.layer > 45 and comic.layer < transition.layer, "Shared comic player covers gameplay HUD while retaining transition fade")
	check(comic._hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and comic._hint.get_theme_font_size("font_size") == 18 \
		and comic._hint.offset_top == -40.0 and comic._hint.offset_bottom == -8.0,
		"Forest uses the common bottom hint style")
	press()
	await create_timer(0.3).timeout
	clear_scene()
	check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Interrupted comic does not record forest arrival")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_FOREST_ENTRY) == SaveProgressService.CinematicStatus.UNHANDLED, "Interrupted comic does not record viewing")
	comic = await enter(COMIC)
	check(comic.panel_index == 0, "Interrupted first visit restarts full comic")

	# Use the real town gate, preserving current town BGM through the comic.
	await at_gate()
	var town_music := transition.current_music_path
	var start_position := transition.music_player.get_playback_position()
	press()
	check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Gate press does not record arrival")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == COMIC, "Town gate routes into comic scene")
	if current_scene.scene_file_path != COMIC:
		quit(1)
		return
	comic = current_scene
	check(transition.current_music_path == town_music, "Town BGM continues throughout incoming comic transition")
	check(transition.music_player.get_playback_position() > start_position, "Town BGM playback position advances rather than restarting")
	press(KEY_E, true)
	check(comic.panel_index == 0, "Held-key echoes do not skip panels")
	for i in range(6):
		check(comic.panel_index == i and comic._image.texture == comic.PANELS[i], "Correct artwork and order for panel %d" % (i + 1))
		check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Panel %d does not finish arrival early" % (i + 1))
		await capture("forest_comic_%02d" % (i + 1))
		if i == 1: click()
		elif i == 2: press(KEY_SPACE)
		elif i == 3: press(KEY_ENTER)
		else: press()
		if i == 0:
			press()
			check(comic.panel_index == 1, "Rapid double input cannot skip fading panel")
		if i < 5: await create_timer(0.3).timeout
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == MIST, "Sixth panel leads into actual forest")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_FOREST_ENTRY) == SaveProgressService.CinematicStatus.WATCHED, "Watching six panels stores separate viewing record")
	check(save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Actual forest arrival records first entry")
	check(not save.has_completed(SaveProgressService.STORY_C1_YUPO_MET), "Comic does not complete Yupo conversation")
	check(transition.current_music_path == Chapter1Music.FOREST.resource_path, "Forest music begins at actual forest boundary")
	check(current_scene.get("player") != null and not current_scene.player.input_frozen, "Forest restores player control")
	var config := ConfigFile.new()
	config.load(SaveProgressService.SAVE_PATH)
	check(config.get_value("progress", String(SaveProgressService.STORY_C1_FOREST_ENTERED), false), "Arrival persisted to disk")
	await capture("forest_comic_arrival")

	# Reopen saved progress: revisit is selected by the independent viewing record.
	clear_scene()
	save._loaded = false
	save.load_progress()
	await at_gate()
	press()
	await create_timer(2.8).timeout
	check(current_scene.scene_file_path == COMIC, "Revisit still uses comic transition")
	if current_scene.scene_file_path == COMIC:
		comic = current_scene
		check(comic._revisit and comic.panel_index == 3, "Revisit shows only page 2 first panel")
		check(comic._image.texture == comic.PANELS[3], "Revisit uses isolated forest-path frame")
		press()
		click()
		check(comic.panel_index == 3, "Revisit input never reveals other panels")
		await capture("forest_comic_revisit")
	await create_timer(4.0).timeout
	check(current_scene.scene_file_path == MIST, "Single-panel revisit automatically enters forest")

	# Reaching the map by another route does not prove this comic was watched.
	clear_scene()
	_seed_progress(true)
	comic = await enter(COMIC)
	check(not comic._revisit and comic.panel_index == 0, "Legacy entry fact cannot fabricate viewing of new comic")
	clear_scene()
	await create_timer(1.2).timeout
	check(current_scene == null and not transition.is_transitioning, "Leaving unhandled comic does not force automatic entry")

	_seed_progress()
	comic = await enter(COMIC)
	press(KEY_ESCAPE)
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_FOREST_ENTRY) == SaveProgressService.CinematicStatus.SKIPPED, "Esc records explicit skip")
	check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Skipping presentation does not fabricate map arrival")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == MIST and save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Skipped comic still enters playable forest normally")
	clear_scene()
	save.load_progress()
	comic = await enter(COMIC)
	check(comic._revisit and comic.panel_index == 3, "Skipped cinematic uses short transition after reload")
	clear_scene()
	await create_timer(1.2).timeout
	check(current_scene == null and not transition.is_transitioning, "Leaving short revisit cancels its delayed transition")
	print("FOREST ENTRY COMIC: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

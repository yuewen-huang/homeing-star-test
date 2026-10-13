extends SceneTree

## Run headless for logic; pass an output directory with a renderer for captures.
class MemorySave extends SaveProgressService:
	func save_progress() -> bool:
		return true

class FailedSave extends SaveProgressService:
	func save_progress() -> bool:
		return false

var failures := 0
var checks := 0
var capture_dir := ""

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func capture(filename: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(filename + ".png"))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		capture_dir = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var scene_path := "res://scenes/sideview/chapter_1_mist_room.tscn"
	var fixture := MemorySave.new()
	fixture._loaded = true
	check(fixture.get_unlocked_stele_destinations().is_empty(), "Locked destinations excluded")
	fixture._config.set_value("steles", "mist_puzzle_entry", 1)
	check(fixture.get_unlocked_stele_destinations().size() == 1, "Legacy unlocked entry is available before completion")
	check(fixture.save_stele_checkpoint(&"first", scene_path, Vector2(900, 555), "第一碑"), "First destination registers")
	check(fixture.save_stele_checkpoint(&"second", scene_path, Vector2(1500, 555), "第二碑"), "Second destination registers")
	var destinations := fixture.get_unlocked_stele_destinations()
	check(destinations.size() == 3, "Two steles in the same map both remain available")
	for destination in destinations:
		if destination.stele_id == &"first":
			check(destination.position == Vector2(900, 555) and destination.title == "第一碑", "First destination retains its own position and name")
	fixture._config.set_value("steles", "first", 0)
	check(fixture.get_unlocked_stele_destinations().size() == 2, "State rechecked when listing")
	fixture.save_stele_checkpoint(&"missing", "res://missing_scene.tscn", Vector2.ZERO, "无效碑")
	check(fixture.get_unlocked_stele_destinations().size() == 2, "Missing scenes excluded")
	fixture.free()
	var failed := FailedSave.new()
	failed._loaded = true
	check(not failed.save_stele_checkpoint(&"failed", scene_path, Vector2.ZERO), "Failed write reported")
	check(not failed._config.has_section("stele_destinations") and failed.get_stele_state(&"failed") == 0, "Failed write rolls back destination and unlock together")
	failed.free()

	var save := root.get_node("SaveProgress") as SaveProgressService
	var original_file := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original_config := save._config.encode_to_text()
	save._config.set_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), false)
	var town = load("res://scenes/sideview/homeward_town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	await process_frame
	var stele := town.world_root.get_node("TownTravelStele") as TownTravelStele
	check(not stele.visible and not stele._prompt.available, "Town stele hidden before master victory")
	save._config.set_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), true)
	save.progress_changed.emit()
	check(stele.visible and stele._prompt.available, "Town stele appears when gate unlocks")
	town.player.position = Vector2(450, 555)
	await process_frame
	await process_frame
	await capture("town_travel_stele")
	save._config.erase_section("steles")
	key(KEY_E)
	await process_frame
	check(is_instance_valid(stele._menu) and stele._menu.destinations.is_empty(), "E opens an empty destination menu")
	await capture("town_travel_empty")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and stele._menu == null, "Esc cancels and restores world")
	save._config.set_value("steles", "mist_puzzle_entry", 1)
	key(KEY_E)
	await process_frame
	check(paused and stele._menu.destinations.size() == 1, "Unlocked entry appears without requiring minigame completion")
	await capture("town_travel_menu")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var music := transition.music_player.stream
	var playback := transition.music_player.get_playback_position()
	key(KEY_ENTER)
	check(not paused and transition.is_transitioning, "Selecting destination resumes and starts transition")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == scene_path, "Arrives in selected map")
	check(absf(current_scene.player.position.x - 336.0) < 1.0, "Arrives beside selected stele")
	check(transition.music_player.stream == music and transition.music_player.get_playback_position() > playback, "Teleport preserves BGM and playback")
	await capture("town_travel_arrival")
	save._config = ConfigFile.new()
	save._config.parse(original_config)
	var restore := FileAccess.open(SaveProgressService.SAVE_PATH, FileAccess.WRITE)
	restore.store_buffer(original_file)
	restore.close()
	print("TOWN TRAVEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

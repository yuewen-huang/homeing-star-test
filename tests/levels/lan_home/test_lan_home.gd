extends SceneTree
const Home := preload("res://scripts/levels/lan_home/lan_home.gd")
const Collection := preload("res://scripts/levels/lan_home/home_collection.gd")
const HOME_SCENE := "res://scenes/levels/lan_home/lan_home.tscn"
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var save: MemorySave
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func wait_frames() -> void:
	await process_frame
	await process_frame
func capture(name_: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await wait_frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name_ + ".png")) == OK, "capture " + name_)
func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	check(not Home.is_unlocked(save), "home stays closed before town completion")
	var before := save._config.encode_to_text()
	for index in Collection.COMICS.size():
		var panels := Collection.comic_panels(index)
		check(not panels.is_empty() and panels.all(func(panel: Texture2D): return panel != null), "all artwork available: " + Collection.COMICS[index][0])
	check(save._config.encode_to_text() == before, "extracting every comic has no story or reward side effects")
	for entry in Collection.MUSIC:
		var track := load(entry[1]) as AudioStream
		check(track != null and track.get_length() > 0, "playable BGM: " + entry[0])
	var town := (load("res://scenes/levels/town/homeward_town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	current_scene = town
	check(not town.home_entry_prompt.available, "first house portal is locked in the actual town")
	# Seed completed town tasks, then finish the same master-victory fact used by town exits.
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			save._config.set_value("progress", String(value), true)
	save.try_complete_fact(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED)
	check(Home.is_unlocked(save) and town.home_entry_prompt.available, "town completion opens the existing first-house door")
	town.player.position = Vector2(350, 555)
	town.player.set_input_frozen(false)
	town._unhandled_input(key(KEY_E))
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == HOME_SCENE, "E at the first door enters Lan's home")
	var home: Node = current_scene
	check(is_equal_approx(home.player.position.y, home.FLOOR_Y), "Lan stands on the resized room's floor")
	var room_art := home.get_node("RoomArt") as Sprite2D
	check(room_art.texture.get_width() * room_art.scale.x < 640.0 and home.player.scale == Vector2.ONE,
		"The room is smaller in world units and uses Lan's regular size")
	Input.action_press(&"ui_right")
	for i in 180:
		if home.player.position.x >= 375.0 * home.ROOM_SCALE:
			break
		await physics_frame
	Input.action_release(&"ui_right")
	await create_timer(2.4).timeout
	await capture("home_room")
	Input.action_press(&"ui_right")
	for i in 180:
		if home.player.position.x >= home.BOOK_X - 8.0:
			break
		await physics_frame
	Input.action_release(&"ui_right")
	check(absf(home.player.position.x - home.BOOK_X) < 16.0 and is_equal_approx(home.player.position.y, home.FLOOR_Y),
		"Actual movement reaches the relocated storybook on the resized floor")
	before = save._config.encode_to_text()
	home._unhandled_input(key(KEY_E))
	var book: Node = home.modal
	check(paused and home.player.input_frozen and book.chapter_list.item_count == Collection.COMICS.size(), "E opens the window with its full comic list")
	check(book.panels.size() == Collection.comic_panels(0).size() and book.page.texture_normal == book.panels[0], "Reader opens the first full comic panel")
	await capture("home_book_reading")
	book._input(key(KEY_RIGHT))
	check(book.page_index == 1 and book.page.texture_normal == book.panels[1], "Right switches to the very next panel immediately")
	book._input(key(KEY_LEFT))
	book._input(key(KEY_LEFT))
	check(book.page_index == 0, "Left returns to the first panel and clamps at its boundary")
	book.page.pressed.emit()
	await wait_frames()
	check(book.zoomed and not book.chapter_list.visible and book._window.size.is_equal_approx(book.ZOOM_SIZE),
		"Clicking the panel opens the larger reader window")
	await capture("home_book_enlarged")
	book._input(key(KEY_ESCAPE))
	check(not book.zoomed and book.chapter_list.visible and home.modal == book, "Esc leaves enlargement before closing the window")
	book.chapter_list.item_selected.emit(Collection.COMICS.size() - 1)
	check(book.comic_index == Collection.COMICS.size() - 1 and book.page_index == 0, "The last comic is accessible and opens on its first panel")
	book._input(key(KEY_ESCAPE))
	await wait_frames()
	check(not paused and not home.player.input_frozen and home.modal == null, "Closing the window restores the original pause and input state")
	check(save._config.encode_to_text() == before, "replay never marks comics watched or grants progress/rewards")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var original_music := transition.music_player.stream
	var original_path := transition.current_music_path
	var cabinet_click := InputEventMouseButton.new()
	cabinet_click.position = home.get_global_transform_with_canvas() * Vector2(home.MUSIC_X, 330.0 * home.ROOM_SCALE)
	cabinet_click.button_index = MOUSE_BUTTON_LEFT
	cabinet_click.pressed = true
	root.push_input(cabinet_click)
	cabinet_click = cabinet_click.duplicate()
	cabinet_click.pressed = false
	root.push_input(cabinet_click)
	var music_view: Node = home.modal
	check(is_instance_valid(music_view) and music_view.has_method("choose_track"),
		"Clicking the scaled record cabinet still opens the music window")
	music_view.choose_track(0)
	check(home.music.playing and transition.music_player.stream_paused, "home playback pauses global BGM without layering two tracks")
	music_view.step_track(1)
	check(home.selected_track == 1 and home.music.stream.data == (load(Collection.MUSIC[1][1]) as AudioStreamMP3).data, "next track loads the selected BGM")
	music_view.toggle_pause()
	check(home.music.stream_paused, "BGM can be paused")
	music_view.toggle_pause()
	check(not home.music.stream_paused, "BGM can resume")
	music_view.seek_slider.value = 10
	check(home.music.get_playback_position() >= 9, "track position can be scrubbed")
	await capture("home_music")
	music_view._input(key(KEY_ESCAPE))
	await wait_frames()
	check(home.music.playing and not paused and home.modal == null, "closing the cabinet continues listening at home")
	home.open_storybook()
	check(home.music.playing, "music continues while browsing comics")
	home.modal.close()
	await wait_frames()
	check(save._config.encode_to_text() == before, "listening changes no inventory, story or cinematic facts")
	home.player.position.x = home.DOOR_X
	home._unhandled_input(key(KEY_E))
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == "res://scenes/levels/town/homeward_town.tscn", "home door returns to town")
	check(absf(current_scene.player.position.x - 350) < 1, "return lands at the first house")
	check(transition.music_player.stream == original_music and transition.current_music_path == original_path and not transition.music_player.stream_paused, "leaving restores the original town music stream")
	current_scene.free()
	current_scene = null
	# Teardown must also restore a world paused by an open book.
	home = (load(HOME_SCENE) as PackedScene).instantiate()
	root.add_child(home)
	current_scene = home
	home.open_storybook()
	home.free()
	current_scene = null
	check(not paused, "tearing down home with its book open cannot leave the world paused")
	transition.music_player.stop()
	print("LAN HOME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

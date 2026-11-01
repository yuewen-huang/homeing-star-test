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
	home.player.set_physics_process(false)
	check(home.player.position.y == home.FLOOR_Y, "Lan stands on the home's walkable floor")
	await capture("home_room")
	before = save._config.encode_to_text()
	home.open_storybook()
	var book: Node = home.modal
	check(paused and home.player.input_frozen and book.content_buttons.size() == Collection.COMICS.size(), "book opens its full contents and freezes gameplay")
	await capture("home_book_contents")
	book.select_comic(0)
	check(book.panels.size() == Collection.comic_panels(0).size() and book.pages[0].texture_normal != null, "book uses the complete original comic rather than revisit playback")
	await capture("home_book_reading")
	book.turn_page(1)
	await create_timer(0.5, true, false, true).timeout
	check(book.page_index == 2 and not book.turning, "animated forward page turn completes while the world is paused")
	book.turn_page(-1)
	await create_timer(0.5, true, false, true).timeout
	check(book.page_index == 0, "book supports reading backwards")
	book.enlarge_page(0)
	check(is_instance_valid(book.zoom), "a comic page can be enlarged")
	await capture("home_book_enlarged")
	book._input(key(KEY_ESCAPE))
	check(book.zoom == null and home.modal == book, "Esc leaves enlargement before closing the book")
	book.show_contents()
	book.select_comic(Collection.COMICS.size() - 1)
	check(book.comic_index == Collection.COMICS.size() - 1, "later comics are freely viewable")
	book.close()
	await wait_frames()
	check(not paused and not home.player.input_frozen and home.modal == null, "closing book restores the original pause and input state")
	check(save._config.encode_to_text() == before, "replay never marks comics watched or grants progress/rewards")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var original_music := transition.music_player.stream
	var original_path := transition.current_music_path
	home.open_music()
	var music_view: Node = home.modal
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

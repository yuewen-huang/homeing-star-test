extends SceneTree
## Run ONLY inside tools/prepare_title_opening.ps1's isolated resource mirror.
const TITLE := "res://scenes/ui/title_menu.tscn"
const OPENING := SaveProgressService.OPENING_SCENE
const TOWN := SaveProgressService.TOWN_START_SCENE
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
const Collection := preload("res://scripts/levels/lan_home/home_collection.gd")
const Book := preload("res://scripts/levels/lan_home/home_storybook.gd")
class RefusingSave extends SaveProgressService:
	func _ready() -> void: pass
	func _write_new_journey(_next: ConfigFile) -> bool: return false
	func save_progress() -> bool: return false

var checks := 0
var failures := 0
var save: SaveProgressService
var transition: SceneTransitionService
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	root.push_input(event)
func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func settle(seconds := 0.32) -> void:
	await create_timer(seconds, true, false, true).timeout
	# Native software/remote rendering can clamp animation delta while real-time
	# timers still elapse. Wait on actual UI readiness, not a guessed frame rate.
	var deadline := Time.get_ticks_msec() + 20000
	while transition.is_transitioning or (is_instance_valid(current_scene)
			and current_scene is ComicPlayer and current_scene._changing_panel):
		if Time.get_ticks_msec() > deadline:
			check(false, "presentation became ready within twenty seconds")
			break
		await process_frame
func enter(path: String) -> Node:
	check(change_scene_to_file(path) == OK, "load " + path.get_file())
	await process_frame
	await process_frame
	return current_scene
func capture(label_: String) -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_ + ".png")) == OK, "capture " + label_)

func run() -> void:
	if not ProjectSettings.globalize_path("res://").replace("\\", "/").contains("/artifacts/title-opening/project"):
		push_error("Refusing tests outside isolated title-opening project")
		quit(2)
		return
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	save = root.get_node("SaveProgress")
	transition = root.get_node("SceneTransition")
	save.reset_all()
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var menu := await enter(TITLE)
	check(not menu.continue_button.visible and root.gui_get_focus_owner() == menu.new_button, "fresh menu defaults to new journey")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before, "opening menu does not write save")
	await capture("01_title_new")
	key(KEY_B)
	key(KEY_F10)
	check(not (root.get_node("InventoryScreen") as InventoryUI).visible, "backpack cannot open behind title")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before, "title blocks unrelated development input")
	key(KEY_DOWN)
	await process_frame
	check(root.gui_get_focus_owner() == menu.menu_buttons[2], "keyboard moves from new journey to settings")
	key(KEY_ENTER)
	await process_frame
	var settings := root.get_node("AudioSettings") as AudioSettingsService
	check(settings.settings_panel.visible and paused, "keyboard opens existing audio settings")
	key(KEY_B)
	key(KEY_F10)
	check(not (root.get_node("InventoryScreen") as InventoryUI).visible and FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before, "settings on title also blocks backpack and save reset")
	await capture("02_settings")
	key(KEY_ESCAPE)
	await process_frame
	check(not settings.settings_panel.visible and not paused, "Esc returns from settings")
	check(root.gui_get_focus_owner() == menu.menu_buttons[2], "settings returns focus to original button")
	menu.new_button.grab_focus()
	key(KEY_ENTER)
	key(KEY_ENTER)
	check(save.has_journey() and transition.is_transitioning, "new game commits once then locks entry")
	check(save.get_resume_scene() == OPENING, "interrupted new journey resumes opening")
	await settle(2.8)
	check(current_scene.scene_file_path == OPENING, "new journey enters opening")
	var comic: Node = current_scene
	check(comic.panel_index == 0 and not save.has_completed(SaveProgressService.STORY_MOVE_TUTORIAL_STARTED), "no key leaks into opening or tutorial")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_OPENING) == SaveProgressService.CinematicStatus.UNHANDLED, "starting comic does not claim watched")
	await capture("opening_01_star_left")
	key(KEY_B)
	check(not (root.get_node("InventoryScreen") as InventoryUI).visible, "backpack cannot open behind opening")
	key(KEY_E, true)
	check(comic.panel_index == 0, "held-key echo cannot advance comic")
	key(KEY_E)
	key(KEY_E)
	check(comic.panel_index == 1, "rapid double press advances only one panel")
	await settle()
	await capture("opening_02_departure")
	check(comic._frames.size() == 12, "opening contains all twelve narrative beats")
	for index in range(2, comic._frames.size()):
		key(KEY_SPACE if index % 2 == 0 else KEY_ENTER)
		await settle()
		check(comic.panel_index == index, "reading reaches narrative beat %d" % (index + 1))
		await capture("opening_%02d" % (index + 1))
	check(comic.panel_index == 11, "twelve authored panels preserve reading order")
	var music_position := transition.music_player.get_playback_position()
	key(KEY_ENTER)
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_OPENING) == SaveProgressService.CinematicStatus.WATCHED, "completion commits watched result")
	await settle(2.8)
	check(current_scene.scene_file_path == TOWN, "completed comic enters actual town")
	check(save.has_completed(SaveProgressService.STORY_MOVE_TUTORIAL_STARTED), "actual town starts existing movement tutorial")
	check(not save.has_completed(SaveProgressService.TUTORIAL_MOVE), "comic never completes movement for player")
	check(transition.music_player.get_playback_position() > music_position, "morning music continues across comic and town")
	await capture("07_town_handoff")
	# Real player input, not a synthetic tutorial fact.
	var move := InputEventKey.new()
	move.physical_keycode = KEY_D
	move.keycode = KEY_D
	move.pressed = true
	Input.parse_input_event(move)
	await settle(0.8)
	move.pressed = false
	Input.parse_input_event(move)
	check(save.has_completed(SaveProgressService.TUTORIAL_MOVE), "player can move and complete existing first tutorial")
	menu = await enter(TITLE)
	check(menu.continue_button.visible and root.gui_get_focus_owner() == menu.continue_button, "existing journey defaults to continue")
	await capture("08_title_continue")
	before = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	click_at(menu.new_button.get_global_rect().get_center())
	check(menu.confirmation.visible and root.gui_get_focus_owner() == menu.cancel_button, "replacement dialog defaults to cancel")
	await capture("09_replace_confirmation")
	key(KEY_ESCAPE)
	check(not menu.confirmation.visible and FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before, "cancel leaves old journey byte-identical")
	menu._request_new_journey()
	menu._start_new_journey()
	var backed_up := false
	for filename in DirAccess.get_files_at(SaveProgressService.SAVE_DIR):
		if filename.begins_with("progress_before_new_") and FileAccess.get_file_as_bytes(SaveProgressService.SAVE_DIR.path_join(filename)) == before:
			backed_up = true
	check(backed_up, "new journey preserves exact previous save as backup")
	check(not save.has_completed(SaveProgressService.TUTORIAL_MOVE), "new journey clears old ability progress")
	await settle(2.8)
	key(KEY_ESCAPE)
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_OPENING) == SaveProgressService.CinematicStatus.SKIPPED, "Esc records skip separately")
	await settle(2.8)
	check(current_scene.scene_file_path == TOWN and not paused, "skip hands control to same town")
	check(save.has_completed(SaveProgressService.STORY_MOVE_TUTORIAL_STARTED) and not save.has_completed(SaveProgressService.TUTORIAL_MOVE), "skip has same initial ability state as watching")
	# Reload an interrupted opening, without imposing it on legacy saves.
	await enter(TITLE)
	check(save.begin_new_journey(), "create interrupted journey fixture")
	save.load_progress()
	check(save.get_resume_scene() == OPENING, "disk reload preserves interrupted opening")
	menu = await enter(TITLE)
	menu._continue_journey()
	await settle(2.8)
	check(current_scene.scene_file_path == OPENING and current_scene.panel_index == 0, "continue actually restores opening at readable first panel")
	await enter(TITLE)
	save.reset_all()
	save.try_complete_fact(SaveProgressService.TUTORIAL_MOVE)
	check(save.has_journey() and save.get_resume_scene() == TOWN, "legacy town save continues without new intro")
	check(save.save_stele_checkpoint(&"mist_puzzle_entry", MIST, Vector2(336, 555)), "real checkpoint fixture committed")
	save.load_progress()
	menu = await enter(TITLE)
	menu._continue_journey()
	await settle(2.8)
	check(current_scene.scene_file_path == MIST, "continue enters actual last checkpoint scene")
	check(absf(current_scene.player.position.x - 336.0) < 2.0, "continue restores checkpoint position")
	await capture("10_continue_checkpoint")
	await enter(TITLE)
	save._config.set_value("checkpoints", "last_scene", "res://missing_scene.tscn")
	check(save.get_resume_scene() == TOWN, "invalid checkpoint safely falls back to town")
	var failing := RefusingSave.new()
	failing._loaded = true
	failing._config.set_value("progress", "old_fact", true)
	var memory_before := failing._config.encode_to_text()
	check(not failing.begin_new_journey() and failing._config.encode_to_text() == memory_before, "failed new save leaves old memory intact")
	check(not failing.finish_cinematic(SaveProgressService.CINEMATIC_OPENING) and failing.get_cinematic_status(SaveProgressService.CINEMATIC_OPENING) == SaveProgressService.CinematicStatus.UNHANDLED, "failed cinematic save rolls back watched claim")
	failing.free()
	var story_before := save._config.encode_to_text()
	check(Collection.comic_panels(0).size() == 12 and save._config.encode_to_text() == story_before, "storybook extracts twelve panels without progression callbacks")
	var book := Book.new()
	root.add_child(book)
	for button: Button in book.content_buttons:
		check(button.position.x + button.size.x <= 1140 and button.position.y + button.size.y < 576, "storybook entry stays inside two-page contents: " + button.text)
	check(book.content_buttons.size() == Collection.COMICS.size(), "all thirteen comics remain accessible")
	# Hide title only for the independent gallery capture.
	current_scene.hide()
	await capture("11_storybook_contents")
	book.select_comic(0)
	await capture("12_storybook_opening")
	for page in 5:
		book.turn_page(1)
		if book.turning:
			await book.turn_tween.finished
	check(book.page_index == 10 and book.pages[0].texture_normal == Collection.comic_panels(0)[10]
		and book.pages[1].texture_normal == Collection.comic_panels(0)[11], "storybook reaches final pair of twelve-panel opening")
	await capture("13_storybook_opening_last")
	check(save._config.encode_to_text() == story_before, "opening replay never writes progress")
	book.free()
	current_scene.show()
	print("TITLE_OPENING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

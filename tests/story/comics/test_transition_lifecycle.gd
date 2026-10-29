extends "../../support/harness.gd"
## All shipped comic readers, modal input, save retries and independently freed hints.
class AuditSave extends SaveProgressService:
	var fail_writes := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_writes
	func show_toast(_text: String) -> void: pass

class Routing extends SceneTransitionService:
	var destinations: Array[String] = []
	func _ready() -> void: pass
	func transition_to(path: String, _music: AudioStream = null) -> void:
		destinations.append(path)

class IdleGuide extends OpeningGuide:
	func _ready() -> void: set_process(false)

const COMICS := ["back_alley_entry", "back_alley_pill", "navigation_hall_entry",
	"navigation_hall_exit", "forest_entry", "wind_sighting", "deer_intro",
	"master_dodge", "salt_to_mirror_lake", "salt_cave_scroll_to_mirror_lake"]

func key(comic: ComicPlayer, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	comic._input(event)

func run() -> void:
	var previous_save := use_memory_progress()
	root.remove_child(previous_save)
	previous_save.free()
	var save := AuditSave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	(root.get_node("QuestLog") as QuestLogService)._save = save
	var original_transition := root.get_node("SceneTransition")
	root.remove_child(original_transition)
	var routing := Routing.new()
	routing.name = "SceneTransition"
	root.add_child(routing)
	var settings := root.get_node("AudioSettings") as AudioSettingsService
	for id in COMICS + ["aberration_escape"]:
		save._config = ConfigFile.new()
		var comic: ComicPlayer = AberrationEscapeComic.new() if id == "aberration_escape" else load("res://scenes/story/comics/%s_comic.tscn" % id).instantiate()
		var completions := [0]
		comic.playback_finished.connect(func(_skipped): completions[0] += 1)
		root.add_child(comic)
		comic.set_process(false)
		check(not comic._frames.is_empty() and comic._frames.all(func(frame): return frame != null), id + ": all production panels load")
		comic._show_panel(1, true)
		var fade: Tween = comic._fade_tween
		comic._show_panel(0, false)
		check(not fade.is_valid(), id + ": replacing a panel cancels its previous fade")
		settings.settings_panel.show()
		check(settings.layer > comic.layer, id + ": settings remain visible above the comic")
		var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
		if id == "master_dodge" and not output.is_empty() and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("comic_settings_overlay.png"))
		key(comic, KEY_E)
		key(comic, KEY_ESCAPE)
		comic.auto_hold_duration = 0.1
		comic._auto_remaining = 0.1
		comic._process(0.2)
		check(comic.panel_index == 0 and not comic._finished and comic._auto_remaining == 0.1, id + ": settings block advance, skip and short-play countdown")
		settings.settings_panel.hide()
		comic.auto_hold_duration = -1
		comic._auto_remaining = -1
		comic._show_panel(comic._frames.size() - 1, false)
		comic._request_finish(false)
		comic._request_finish(true)
		check(completions[0] == 1, id + ": completion settles once under repeated input")
		comic.free()
	await wait_frames(3)
	for row in [["back_alley_entry", SaveProgressService.STORY_BACK_ALLEY_ENTERED],
			["back_alley_pill", SaveProgressService.QUEST_BACK_ALLEY_STEP],
			["navigation_hall_exit", SaveProgressService.QUEST_LAN_AND_WIND_STEP]]:
		save._config = ConfigFile.new()
		save.fail_writes = true
		var comic := load("res://scenes/story/comics/%s_comic.tscn" % row[0]).instantiate() as ComicPlayer
		root.add_child(comic)
		comic._show_panel(comic._frames.size() - 1, false)
		var before := routing.destinations.size()
		key(comic, KEY_E)
		check(comic._pending_completion_retry and routing.destinations.size() == before and not save.has_completed(row[1]), row[0] + ": failed save rolls back progress and blocks travel")
		save.fail_writes = false
		key(comic, KEY_E)
		check(comic._finished and routing.destinations.size() == before + 1 and save.has_completed(row[1]), row[0] + ": explicit retry persists before one scene change")
		comic.free()
	save._config = ConfigFile.new()
	save.fail_writes = true
	var reader := load("res://scenes/story/comics/wind_sighting_comic.tscn").instantiate() as WindSightingComic
	root.add_child(reader)
	reader._request_finish(true)
	var abandoned := [0]
	reader.abandoned.connect(func(): abandoned[0] += 1)
	settings.settings_panel.show()
	key(reader, KEY_ESCAPE)
	check(abandoned[0] == 0, "Failed-save dismissal cannot consume settings Esc")
	settings.settings_panel.hide()
	routing.is_transitioning = true
	key(reader, KEY_ESCAPE)
	check(abandoned[0] == 0, "Failed-save dismissal cannot interrupt the map fade")
	routing.is_transitioning = false
	reader.input_enabled = false
	key(reader, KEY_ESCAPE)
	check(abandoned[0] == 0, "Disabled reader cannot dismiss a failed save")
	reader.input_enabled = true
	key(reader, KEY_ESCAPE)
	key(reader, KEY_ESCAPE)
	check(abandoned[0] == 1 and save.get_cinematic_status(reader.cinematic_id) == SaveProgressService.CinematicStatus.UNHANDLED, "Abandoning emits once and does not invent viewing progress")
	reader.free()
	save.fail_writes = false
	var host := Node2D.new()
	root.add_child(host)
	var guide := IdleGuide.new()
	host.add_child(guide)
	var crate := Sprite2D.new()
	host.add_child(crate)
	var before := get_processed_tweens()
	guide._add_crate_marker(crate)
	var loops := get_processed_tweens().filter(func(tween): return not before.has(tween))
	check(loops.size() == 1, "Crate marker starts one breathing loop")
	crate.free()
	await wait_frames(3)
	check(is_instance_valid(guide) and loops.all(func(tween): return not tween.is_valid()), "Deleting the crate ends its loop while the opening guide survives")
	var target := Node2D.new()
	host.add_child(target)
	var hint := NpcTargetHint.new()
	before = get_processed_tweens()
	hint.configure(target)
	loops = get_processed_tweens().filter(func(tween): return not before.has(tween))
	hint._keycap_root.free()
	hint._marker_root.free()
	await wait_frames(3)
	check(loops.size() == 2 and loops.all(func(tween): return not tween.is_valid()), "Deleted E/target visuals cannot leave looping tweens on their hint controller")
	save._config = ConfigFile.new()
	save.try_complete_fact(SaveProgressService.STORY_MAGIC_SHOP_TALK)
	save.add_item(ItemCatalog.HANGOVER_PILL)
	var inventory := InventoryUI.new()
	host.add_child(inventory)
	inventory.visible = true
	inventory._select_category(InventoryUI.CATEGORIES.find(ItemCatalog.CATEGORY_QUEST))
	var pulse: Tween = inventory._hangover_pill_pulse
	check(pulse != null and pulse.is_valid(), "Inventory item highlight starts a real breathing loop")
	inventory._hangover_pill_highlight.free()
	await wait_frames(3)
	check(not pulse.is_valid(), "Replacing inventory visuals cannot leave a loop on a freed highlight")
	inventory.close_inventory()
	host.queue_free()
	await wait_frames(3)
	routing.free()
	root.add_child(original_transition)
	expect_save_untouched()
	finish("TRANSITION LIFECYCLE")

extends SceneTree

## TravelCatalog and the town travel menu: the catalog matches the steles placed in
## the maps, the menu model marks locked/unlocked/completed steles, and the window
## shows region tabs with stele cards. With -Visual the menu is captured over the
## town to HOMING_STAR_TEST_OUTPUT. Progress lives in memory only.
class MemorySave extends SaveProgressService:
	func save_progress() -> bool:
		return true

const MAP_SCENES := [
	"res://scenes/sideview/chapter_1_mist_room.tscn",
	"res://scenes/sideview/chapter_1_wind_room.tscn",
	"res://scenes/sideview/chapter_1_root_room.tscn",
	"res://scenes/sideview/chapter_1_vine_room.tscn",
	"res://scenes/sideview/chapter_2_salt_field.tscn",
]
const MIST := "res://scenes/sideview/chapter_1_mist_room.tscn"

var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT") if DisplayServer.get_name() != "headless" else ""
	check_catalog_matches_maps()
	check_menu_model()
	await check_menu_window()
	if failures == 0:
		print("PASS: travel catalog matches the maps; menu shows region tabs, locked silhouettes and travel cards")
	quit(1 if failures else 0)

## Every catalog stele is placed in a map with the same kind, and every map stele is catalogued.
func check_catalog_matches_maps() -> void:
	var placed := {}
	for path: String in MAP_SCENES:
		var room := (load(path) as PackedScene).instantiate()
		for node in room.find_children("*", "", true, false):
			if node is MinigameStele:
				placed[node.stele_id] = node.stele_kind
		room.free()
	var listed := {}
	check(TravelCatalog.CHAPTERS[0] == Chapter1Travel.CHAPTER, "chapter 1 comes from its own file")
	for chapter: Dictionary in TravelCatalog.CHAPTERS:
		for region: Dictionary in chapter.regions:
			check((String(region.emblem).is_empty() or ResourceLoader.exists(region.emblem)) and ResourceLoader.exists(region.music), "region %s has valid optional emblem and music" % region.id)
			for stele: Dictionary in region.steles:
				check(not listed.has(stele.id), "stele %s is catalogued once" % stele.id)
				listed[stele.id] = true
				check(placed.get(stele.id, -1) == stele.kind, "catalog stele %s is placed with kind %d" % [stele.id, stele.kind])
				check(TravelCatalog.region_of(stele.id).id == region.id, "region_of(%s) is %s" % [stele.id, region.id])
	for id: StringName in placed:
		check(listed.has(id), "map stele %s is in the catalog" % id)
	check(TravelCatalog.music_for(&"mist_combat_01") == Chapter1Music.FOREST, "chapter 1 steles travel with the forest BGM")
	check(TravelCatalog.music_for(&"unknown") == null, "unknown steles keep the current BGM")

func check_menu_model() -> void:
	var save := MemorySave.new()
	save._loaded = true
	var chapters := TravelCatalog.menu_chapters(save)
	check(chapters.size() == 1 and chapters[0].id == &"chapter_1", "fresh save: only the first chapter is listed")
	var regions: Array = chapters[0].regions
	check(regions.size() == Chapter1Travel.CHAPTER.regions.size(), "every chapter 1 region is listed even with nothing unlocked")
	var any_open := false
	for region in regions:
		for stele: Dictionary in region.steles:
			any_open = any_open or stele.unlocked
	check(not any_open, "fresh save: every stele is locked")
	save.save_stele_checkpoint(&"wind_combat_high_branches", "res://scenes/sideview/chapter_1_wind_room.tscn", Vector2(2700, 737), "旧名字")
	save.set_stele_state(&"wind_combat_high_branches", MinigameStele.SteleState.COMPLETED)
	save.save_stele_checkpoint(&"future_stele", MIST, Vector2(900, 555), "未登记碑")
	chapters = TravelCatalog.menu_chapters(save)
	var wind: Dictionary = chapters[0].regions[1]
	var combat: Dictionary = wind.steles[1]
	check(wind.id == &"wind" and combat.unlocked and combat.completed and not wind.steles[0].unlocked,
		"unlocked/completed state is per stele")
	check(combat.title == "高枝碑" and combat.destination.position == Vector2(2700, 737),
		"the catalog name wins over the saved one; the saved arrival point is kept")
	check(chapters.size() == 2 and chapters[-1].id == TravelCatalog.OTHER and chapters[-1].regions[0].steles[0].id == &"future_stele",
		"an unlocked stele missing from the catalog still appears under 其他")
	save.free()

func check_menu_window() -> void:
	var save := root.get_node("SaveProgress") as SaveProgressService
	var original := save._config.encode_to_text()
	save._config = ConfigFile.new()
	save._config.set_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), true)
	for id in [&"mist_puzzle_entry", &"mist_combat_01", &"wind_puzzle_directed_bells"]:
		save._config.set_value("steles", String(id), MinigameStele.SteleState.UNLOCKED)
	save._config.set_value("steles", "mist_puzzle_entry", MinigameStele.SteleState.COMPLETED)
	save._config.set_value("stele_destinations", "mist_combat_01", {"scene_path": MIST, "position": Vector2(2180, 551), "title": ""})
	save._config.set_value("stele_destinations", "wind_puzzle_directed_bells",
		{"scene_path": "res://scenes/sideview/chapter_1_wind_room.tscn", "position": Vector2(340, 367), "title": ""})
	var backdrop: Node = null
	if not output.is_empty():
		backdrop = load("res://scenes/sideview/homeward_town.tscn").instantiate()
		root.add_child(backdrop)
		for i in 3: await process_frame
	var menu := SteleTravelMenu.new()
	menu.destinations = save.get_unlocked_stele_destinations()
	menu.chapters = TravelCatalog.menu_chapters(save)
	var chosen: Array[StringName] = []
	menu.destination_selected.connect(func(id): chosen.append(id))
	root.add_child(menu)
	await process_frame
	check(paused, "menu pauses the world")
	var chrome := false
	for node in menu.find_children("*", "", true, false):
		if (node is Label or node is Button) and (String(node.text).contains("Esc") or String(node.text) == "石碑传送"):
			chrome = true
	check(not chrome, "no title bar or Esc button over the window")
	check(menu._chapter_buttons.is_empty(), "one reached chapter: no chapter bar")
	check(menu._tabs.size() == 4 and menu._tabs[0].text.begins_with("雾区") and menu._tabs[0].icon != null,
		"four region tabs with emblems")
	check(menu._tabs[0].text.ends_with("2/2") and menu._tabs[2].text.ends_with("0/2"), "tabs count activated steles")
	var cards := menu._cards.get_children()
	check(cards.size() == 2 and not cards[0].disabled and cards[0].has_focus(), "first open card of the first open region has focus")
	check(_texts(cards[0]).has("解谜碑 · 已完成"), "completed steles say so")
	await capture("travel_menu_mist")
	menu._tabs[2].grab_focus()
	await process_frame
	cards = menu._cards.get_children()
	check(menu._region_index == 2 and cards.size() == 2 and cards[0].disabled and _texts(cards[0]).has("？？？"),
		"focusing a tab shows its region; locked steles are disabled and nameless")
	await capture("travel_menu_locked")
	menu._tabs[1].grab_focus()
	await process_frame
	cards = menu._cards.get_children()
	check(_texts(cards[0]).has("孤枝碑") and cards[1].disabled, "wind region: puzzle open, combat locked")
	cards[0].pressed.emit()
	check(chosen == [&"wind_puzzle_directed_bells"], "pressing a card selects its stele")
	await capture("travel_menu_wind")
	menu.close()
	await process_frame
	check(not paused, "closing restores the world")
	await check_chapter_bar(save)
	if backdrop != null:
		backdrop.queue_free()
		await process_frame
	(root.get_node("SceneTransition") as SceneTransitionService).music_player.stop()
	save._config = ConfigFile.new()
	save._config.parse(original)

## Two chapters: the bar appears and Q/E cycle chapters, rebuilding tabs and cards.
func check_chapter_bar(save: SaveProgressService) -> void:
	var chapters := TravelCatalog.menu_chapters(save)
	var test_steles: Array[Dictionary] = [{"id": &"test_stele", "title": "测试碑", "kind": MinigameStele.SteleKind.COMBAT,
		"unlocked": true, "completed": false, "destination": {"scene_path": MIST, "position": Vector2(900, 555)}}]
	var test_regions: Array[Dictionary] = [{"id": &"test", "title": "测试区", "emblem": null, "steles": test_steles}]
	chapters.append({"id": &"chapter_2", "title": "第二章 · 测试", "regions": test_regions})
	var menu := SteleTravelMenu.new()
	menu.chapters = chapters
	root.add_child(menu)
	await process_frame
	check(menu._chapter_buttons.size() == 2 and menu._chapter_buttons[0].text == "第一章 · 迷雾森林", "two chapters: the bar lists both")
	check(menu._chapter_index == 0 and menu._tabs.size() == 4, "opens on the first chapter with an activated stele")
	await capture("travel_menu_chapters")
	press(KEY_E)
	await process_frame
	check(menu._chapter_index == 1 and menu._tabs.size() == 1 and _texts(menu._cards.get_child(0)).has("测试碑")
		and menu._cards.get_child(0).has_focus(), "E moves to the next chapter and focuses its first stele")
	await capture("travel_menu_chapter_2")
	press(KEY_E)
	await process_frame
	check(menu._chapter_index == 0, "E wraps around to the first chapter")
	press(KEY_Q)
	await process_frame
	check(menu._chapter_index == 1, "Q goes back one chapter")
	menu.close()
	await process_frame

func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)

func _texts(card: Node) -> Array[String]:
	var texts: Array[String] = []
	for label in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts

func capture(filename: String) -> void:
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))

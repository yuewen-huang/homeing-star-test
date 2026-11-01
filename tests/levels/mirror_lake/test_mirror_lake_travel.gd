extends SceneTree

class MemorySave extends SaveProgressService:
	var reject := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not reject
	func is_ability_unlocked(_ability: StringName) -> bool: return true

const LAKE := "res://scenes/levels/mirror_lake/mirror_lake.tscn"
const IDS := [&"mirror_lake_puzzle_01", &"mirror_lake_combat_01"]
const ARRIVALS := [Vector2(5730, 619), Vector2(11490, 619)]
var save: MemorySave
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	# Reproduce a shipped save: both trials completed, no travel records at all.
	for id in IDS: save._config.set_value("steles", String(id), 2)
	for fact in [SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED, MirrorLakeEntry.SEAL_FACT,
		MirrorLakeInkTrial.INTRO_FACT, MirrorLakeInkTrial.SOLVED_FACT]:
		save._config.set_value("progress", String(fact), true)
	var before := save._config.encode_to_text()
	var destinations := save.get_unlocked_stele_destinations()
	check(destinations.size() == 2, "completed legacy lake steles resolve without destination records")
	check(save._config.encode_to_text() == before, "legacy resolution changes neither progress nor latest checkpoint")
	var chapters := TravelCatalog.menu_chapters(save)
	check(chapters.size() == 2 and chapters[1].id == &"chapter_2", "lake alone makes chapter two available")
	var region: Dictionary = chapters[1].regions[1]
	check(region.id == &"mirror_lake" and region.steles.size() == 2, "both lake steles are under chapter two / Mirror Lake")
	check(region.steles.all(func(stele: Dictionary): return stele.unlocked and stele.completed), "each legacy completion is selectable and completed")
	check(TravelCatalog.music_for(IDS[0]) == MirrorLakeMusic.EXPLORE and TravelCatalog.music_for(IDS[1]) == MirrorLakeMusic.EXPLORE, "both destinations choose the lake exploration music")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for index in IDS.size():
		transition.set_scene_entry_position(ARRIVALS[index])
		var lake := (load(LAKE) as PackedScene).instantiate() as MirrorLake
		root.add_child(lake)
		current_scene = lake
		lake.set_process(false)
		lake.player.set_physics_process(false)
		lake.ink_trial.set_physics_process(false)
		check(lake.player.position.is_equal_approx(ARRIVALS[index]), "travel restores the selected stele position %d" % index)
		check(transition.take_scene_entry_position() == Vector2(-1, -1), "arrival is consumed once")
		var stele: MinigameStele = lake.puzzle_stele if index == 0 else lake.ink_trial.combat_stele
		lake.camera_x = lake.camera_x_for(lake.player.position.x)
		lake.update_scroll()
		check(stele.can_interact(), "selected stele remains bound and interactable after scrolling")
		check(stele.checkpoint_position().is_equal_approx(ARRIVALS[index]), "checkpoint uses map coordinates rather than the scrolled screen")
		before = save._config.encode_to_text()
		save.reject = true
		check(not stele.interact() and save._config.encode_to_text() == before, "failed activation rolls back the entire save transaction")
		save.reject = false
		check(stele.interact(), "E interaction registers an explicit destination")
		var record: Dictionary = save._config.get_value("stele_destinations", String(IDS[index]))
		check(record.scene_path == LAKE and record.position.is_equal_approx(ARRIVALS[index]), "explicit destination retains the correct lake and map position")
		current_scene = null
		lake.free()
		await process_frame
	# An explicitly saved destination must continue to override the legacy fallback.
	save.save_stele_checkpoint(IDS[0], LAKE, Vector2(5700, 619), "镜湖 · 解谜碑")
	destinations = save.get_unlocked_stele_destinations()
	for destination in destinations:
		if destination.stele_id == IDS[0]:
			check(destination.position == Vector2(5700, 619), "existing saved positions override fallback coordinates")
	var town := (load("res://scenes/levels/town/homeward_town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	current_scene = town
	var town_stele := town.world_root.get_node("TownTravelStele") as TownTravelStele
	town_stele.open_menu()
	var menu := town_stele._menu
	menu._select_chapter(1)
	menu._select_region(1)
	var cards := menu._cards.get_children()
	check(cards.size() == 2 and cards.all(func(card: Button): return not card.disabled), "town menu exposes two selectable lake cards")
	cards[1].pressed.emit()
	await create_timer(3.0).timeout
	check(current_scene is MirrorLake and current_scene.player.position.distance_to(ARRIVALS[1]) < 1, "choosing the combat stele in town arrives beside that stele")
	check(transition.current_music_path == MirrorLakeMusic.EXPLORE.resource_path, "town travel switches to Mirror Lake BGM")
	current_scene.free()
	current_scene = null
	transition.music_player.stop()
	print("MIRROR LAKE TRAVEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

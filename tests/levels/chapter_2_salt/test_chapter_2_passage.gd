extends SceneTree

const COLLECTION := preload("res://scripts/levels/lan_home/home_collection.gd")
const CHAPTER_2_TEXT := preload("res://scripts/story/chapter_2_dialogue.gd")
const FOREST_FACTS := preload("res://scripts/story/forest_story_facts.gd")
const FRAMES := [
	"01_crossing_the_gate.png", "02_salt_wind.png",
	"03_salt_field.png", "04_before_the_sneeze.png",
]

class MemorySave extends SaveProgressService:
	var fail_write := false
	var disk := ""
	func load_progress() -> void:
		_config = ConfigFile.new()
		if not disk.is_empty(): _config.parse(disk)
		_loaded = true
	func save_progress() -> bool:
		if fail_write: return false
		disk = _config.encode_to_text()
		return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var save: MemorySave
var room: Chapter1DeerBossRoom
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null
func enter() -> void:
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame; await process_frame
func close_reward() -> void:
	if room.story.reward_reveal != null: room.story.reward_reveal._finish_reveal()
	await process_frame; await process_frame
func key(code := KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
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
func wait_transition() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in 600:
		await process_frame
		if not transition.is_transitioning: return
	check(false, "Scene transition completes within 600 frames")

func stand_at_gate() -> void:
	room.player.set_physics_process(false)
	room.player.position = room.story.chapter_gate.position
	room._process(0)
	room.story._process(0)
	(room.get_node("Camera2D") as Camera2D).reset_smoothing()
	await process_frame

func wait_for_panel(comic: WindSightingComic) -> void:
	for frame in 60:
		if not comic._changing_panel: return
		await process_frame
	check(false, "Panel fade settles")

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save)
	real_save.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	# Legacy completed save: no optional quests, steles, reward or presentation records.
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	save.fail_write = true
	await enter()
	check(room.story.reward_pending and not room.story.chapter_gate.visible, "Failed reward save keeps portal locked")
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 0 and not save.has_claimed_reward(DeerStory.REWARD_ID), "Failed grant rolls back item and claim together")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and not paused, "Reward failure retains victory and player control")
	save.fail_write = false
	room.player.reset_after_map_fall(room.story.rematch_prompt.target.position)
	room.player.set_physics_process(false)
	room.story._process(0)
	key()
	await process_frame
	check(room.story.reward_reveal != null and paused and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Entrance interaction retries the unique reward with its existing reveal")
	await capture("chapter2_relic_reward")
	# Closing during a write failure must be retryable without awarding another item.
	save.fail_write = true
	await close_reward()
	check(room.story.reward_pending and not room.story.chapter_gate.visible and not paused, "Presentation write failure leaves safe retry and hidden portal")
	save.fail_write = false
	room.story._settle_reward()
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Presentation retry never duplicates reward")
	# Quit while the reveal is open; re-entry offers it again from saved ownership.
	clear_scene()
	check(not paused, "Interrupted reveal restores scene pause")
	save.load_progress()
	await enter()
	check(room.story.reward_reveal != null and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Reload after interruption resumes reveal without a second grant")
	await close_reward()
	check(room.story.chapter_gate.visible and save.has_completed(DeerStory.REWARD_PRESENTED_ID), "Completed reveal persists and opens portal")
	check(not save.equip_special_item(ItemCatalog.DEER_RELIC), "Placeholder quest relic cannot accidentally occupy the Q combat slot")
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED) \
		and not save.has_completed(SaveProgressService.STORY_C1_FORECOURT_TRACE_SEEN), "Chapter access requires no corpse or trace inspection")
	clear_scene()
	save.load_progress()
	await enter()
	check(room.story.reward_reveal == null and room.story.chapter_gate.visible and not paused, "Completed save restores portal without replaying reward")
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Repeated room entry retains exactly one relic")
	await stand_at_gate()
	await capture("chapter2_gate_unlocked")
	var before_arrival := save.disk
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	transition.play_music(Chapter1Music.FOREST)
	key()
	var comic := room.story.comic
	check(is_instance_valid(comic) and paused and room.player.input_frozen,
		"The official gate opens the entry comic and locks movement")
	if not is_instance_valid(comic):
		print("CHAPTER 2 PASSAGE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var comic_id := DeerStory.SALT_ENTRY_COMIC_ID
	for index in FRAMES.size():
		await wait_for_panel(comic)
		check(comic.panel_index == index and comic._image.texture.resource_path.get_file() == FRAMES[index],
			"Approved panel %d appears in order" % (index + 1))
		await capture("salt_entry_comic_%02d" % (index + 1))
		if index < FRAMES.size() - 1:
			key()
			key()
			check(comic.panel_index == index + 1, "Rapid E cannot advance through a fading panel")
	for frame in 50: await process_frame
	check(comic.panel_index == 3 and not transition.is_transitioning and current_scene == room,
		"The pre-sneeze image waits for a separate advance")
	check(transition.current_music_path == Chapter1Music.FOREST.resource_path
		and not save.has_visited_salt_field() and save.get_cinematic_status(comic_id) == SaveProgressService.CinematicStatus.UNHANDLED,
		"Viewing keeps forest music and writes neither viewing nor arrival early")
	key()
	await wait_transition()
	check(current_scene is Chapter2SaltField, "The finished comic transitions to the official salt field")
	if current_scene is Chapter2SaltField:
		var chapter := current_scene as Chapter2SaltField
		var salt_story = chapter.salt_story
		for frame in 40:
			if salt_story.beat.dialogue != null: break
			await process_frame
		check(chapter.feet.distance_to(Chapter2SaltField.SPAWN) < 2, "Salt field spawns the planar pawn at its entrance")
		check(save.has_visited_salt_field() and save.get_cinematic_status(comic_id) == SaveProgressService.CinematicStatus.WATCHED
			and transition.current_music_path == Chapter2Music.SALT_FIELD.resource_path,
			"First arrival independently preserves viewing and starts the salt field music")
		var entry: TutorialDialogue = salt_story.beat.dialogue
		check(entry != null, "The salt field initiates its entrance dialogue")
		if entry != null:
			for index in CHAPTER_2_TEXT.SALT_ENTRY.size():
				check(entry._label.text == CHAPTER_2_TEXT.SALT_ENTRY[index][1], "Salt field dialogue line %d keeps the script order" % (index + 1))
				if index < 2:
					check(entry.get("_active_cast").has(&"盐伯") == (index == 1),
						"Yanbo joins the cast only after Lan's opening line")
				key()
				await process_frame
				if index == 0: await capture("salt_entry_05_lan_sneeze")
				if index == 1: await capture("salt_entry_06_yanbo")
				key()
				await process_frame
		check(save.has_completed(salt_story.ENTRY_READ) and not paused, "Reading salt elder restores play and records the dialogue separately")
		chapter.set_physics_process(false)
		chapter.feet = Chapter2SaltField.RETURN_POINT
		chapter._sync_view(0)
		key()
		await wait_transition()
		check(current_scene is Chapter1DeerBossRoom, "Return portal transitions back to the first chapter")
		if current_scene is Chapter1DeerBossRoom:
			room = current_scene as Chapter1DeerBossRoom
			check(room.player.position.distance_to(DeerStory.CHAPTER_2_GATE_POSITION) < 2 \
				and room.story.chapter_gate.visible and room.story.reward_reveal == null, "Return arrives beside chapter gate with victory and reward retained")
			save._config.erase_section_key("cinematics", String(comic_id))
			await stand_at_gate()
			key()
			check(room.story.comic == null and transition.is_transitioning, "An old save that already visited the salt field keeps direct entry")
			await wait_transition()
			check(current_scene is Chapter2SaltField and not paused and save.get_cinematic_status(comic_id) == SaveProgressService.CinematicStatus.UNHANDLED,
				"Legacy arrival leaves the new comic and entrance dialogue untouched")
	var storybook_id := -1
	for index in COLLECTION.COMICS.size():
		if COLLECTION.COMICS[index][1] == DeerStory.SALT_ENTRY_COMIC:
			storybook_id = index
			break
	var gallery_snapshot := save.disk
	check(COLLECTION.comic_panels(storybook_id).size() == FRAMES.size() and save.disk == gallery_snapshot,
		"The storybook offers all four panels without replaying progress or arrival")
	clear_scene()
	save.disk = before_arrival
	save.load_progress()
	save.try_complete_facts([FOREST_FACTS.DEER_REVISED_ENDING, FOREST_FACTS.DEER_RELEASE_READ,
		FOREST_FACTS.VINE_STONE_GATE_SEEN])
	await enter()
	await stand_at_gate()
	key()
	check(room.story.dialogue != null and room.story.comic == null, "The revised ending plays Lan's stone-gate dialogue first")
	for tick in 18:
		if room.story.dialogue == null: break
		key()
		await process_frame
	check(save.has_completed(FOREST_FACTS.OLD_ROUTE_READ) and is_instance_valid(room.story.comic),
		"Reading the chapter ending opens the entry comic in the same visit")
	if is_instance_valid(room.story.comic):
		save.fail_write = true
		key(KEY_ESCAPE)
		check(room.story.comic._pending_completion_retry and not transition.is_transitioning,
			"A failed skip save holds the comic and the route")
		key(KEY_ESCAPE)
		check(room.story.comic == null and not paused and not room.player.input_frozen
			and not save.has_visited_salt_field(), "Abandoning a failed save restores the stone gate")
		save.fail_write = false
		await process_frame
		key()
		key(KEY_ESCAPE)
		await wait_transition()
		check(current_scene is Chapter2SaltField and save.get_cinematic_status(comic_id) == SaveProgressService.CinematicStatus.SKIPPED,
			"Explicit skip uses the same entrance and a distinct cinematic outcome")
	clear_scene()
	print("CHAPTER 2 PASSAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

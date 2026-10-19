extends SceneTree

const TOWN := "res://scenes/levels/town/homeward_town.tscn"
const HALL := "res://scenes/levels/navigation_hall/navigation_hall.tscn"
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
var save: SaveProgressService
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func _seed_progress(won := true, climb := true) -> void:
	var config := ConfigFile.new()
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			config.set_value("progress", String(value), not String(value).begins_with("story_c1_"))
	config.set_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), won)
	config.set_value("progress", String(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), true)
	config.set_value("progress", String(SaveProgressService.TUTORIAL_CLIMB), climb)
	# The spirit pendant handover (tested in test_forest_core_relic) precedes the departure talk.
	config.set_value(SaveProgressService.REWARDS_SECTION, String(ForestCoreRelic.REWARD_ID), true)
	config.set_value(SaveProgressService.INVENTORY_SECTION, String(ItemCatalog.SPIRIT_PENDANT), 1)
	config.set_value("progress", String(ForestCoreRelic.PRESENTED_ID), true)
	save._config = config
	save._loaded = true
	save.progress_changed.emit()

func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null

func enter_scene(path: String) -> Node:
	clear_scene()
	var room: Node = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	return room

func press_e() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	root.push_input(key)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	_seed_progress(false)
	var town = await enter_scene(TOWN)
	check(town.get_node_or_null("Chapter1Departure") == null and not town._right_gate_visual.active, "Before master victory no departure dialogue or open gate")
	var log_service := root.get_node("QuestLog") as QuestLogService
	check(log_service.get_track_view().chapter_title != "雾杉森林", "Forest quest hidden before victory")

	clear_scene()
	_seed_progress()
	town = await enter_scene(TOWN)
	var controller = town.get_node("Chapter1Departure")
	check(controller.entries.size() == 3, "Three street dialogue targets use existing NPCs")
	var view := log_service.get_track_view()
	check(view.is_empty(), "First chapter has no automatic main quest after victory")
	check(town.right_gate_hint.available and not town.right_gate_hint.task_guided, "Town gate is open without objective guidance")
	await capture("departure_quest")
	for entry: Dictionary in controller.entries:
		town.player.position = entry.target.position + Vector2(-35, 0)
		await process_frame
		await physics_frame
		press_e()
		await process_frame
		var dialogue: TutorialDialogue = controller.dialogue
		check(dialogue != null and dialogue.opened, "E opens optional dialogue " + String(entry.id))
		if dialogue == null: continue
		check(town.player.input_frozen and not save.has_completed(entry.id), "Conversation freezes movement, saves only after completion")
		var count := dialogue.get_line_progress().y
		await capture("departure_" + String(entry.id))
		dialogue.advance()
		if entry.id == SaveProgressService.STORY_C1_TOWN_MAIDASHU:
			await capture("departure_lan_left")
		for i in count - 1: dialogue.advance()
		check(save.has_completed(entry.id) and not town.player.input_frozen, "Completed optional dialogue recorded and controls restored")
		check(not entry.prompt.available, "Already heard departure dialogue no longer prompts")
	check(save.get_item_count(ItemCatalog.HANGOVER_PILL) == 0, "Shop dialogue does not reissue prologue pill")

	var master: Node2D = town.world_root.get_node("Master")
	town.player.position = master.position + Vector2(-20, 0)
	await create_timer(0.2).timeout
	check(bool(master.get("player_in_range")), "Master area detects Lan after walking-space scroll settles")
	press_e()
	await process_frame
	var master_dialogue: TutorialDialogue = master.get("_dialogue")
	check(master_dialogue != null and master_dialogue.get_line_progress().y == 4, "Master uses four-line T02 after M01")
	if master_dialogue != null:
		for i in 3: master_dialogue.advance()
		await capture("departure_master_long_line")
		master_dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_TOWN_MASTER), "Master departure talk has its own completion record")

	town.player.position = town.eating_guests.position + Vector2(-20, 24)
	await create_timer(0.1).timeout
	check(controller._guest_index == 0 and not town.player.input_frozen, "Guests speak in ambient bubbles without freezing Lan")
	var bubble: CharacterBubble = controller._bubble
	if bubble == null:
		quit(1)
		return
	check(bubble.global_position.distance_to(town.eating_guests.resolve_bubble_anchor(EatingGuestsNpc.Speaker.CAT)) < 1.0, "First bubble anchored to cat at scrolled world position")
	await capture("departure_guests_cat")
	controller._guest_remaining = 0
	controller._update_guests(0)
	check(controller._guest_index == 1 and bubble.global_position.distance_to(town.eating_guests.resolve_bubble_anchor(EatingGuestsNpc.Speaker.DOG)) < 1.0, "Reply anchored to dog on same table art")
	await capture("departure_guests_dog")
	controller._guest_remaining = 0
	controller._update_guests(0)
	controller._guest_remaining = 0
	controller._update_guests(0)
	check(controller._guest_index == -1 and not bubble.visible, "Three-line bubble conversation ends cleanly")
	controller._update_guests(0)
	check(controller._guest_index == -1, "Standing beside table does not repeat conversation")

	# Enter/exit through the real town doorway; chapter one skips old prologue comics.
	town.player.position = Vector2(town.NAVIGATION_DOOR_X, town.STREET_BASELINE)
	await process_frame
	press_e()
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == HALL, "Post-victory town doorway goes directly to hall")
	var hall = current_scene
	controller = hall.get_node("Chapter1Departure")
	hall.player.position.x = hall.navigator.position.x - 30
	await process_frame
	press_e()
	await process_frame
	var dialogue: TutorialDialogue = controller.dialogue
	check(dialogue != null and dialogue.get_line_progress().y == 5, "Navigator has optional five-line T03")
	if dialogue != null:
		for i in 4: dialogue.advance()
		await capture("departure_navigator_long_line")
		dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_TOWN_NAVIGATOR), "Navigator report saved only after conversation")
	hall.player.position.x = hall.EXIT_X + 50
	await process_frame
	press_e()
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == TOWN, "Hall exit returns directly without old Wind comic")
	check(current_scene.get_node("Chapter1Departure").entries.all(func(entry: Dictionary): return not entry.prompt.available), "Completed street conversations remain completed on reload")

	# Incomplete kite quest keeps priority; talking to child must not finish it.
	clear_scene()
	_seed_progress(true, false)
	town = await enter_scene(TOWN)
	controller = town.get_node("Chapter1Departure")
	town.player.position = town.child_npc.position
	await process_frame
	var child_entry: Dictionary = controller.entries[1]
	check(not child_entry.prompt.available, "Unfinished kite quest blocks only child's new conversation")
	press_e()
	await process_frame
	check(controller.dialogue == null and not save.has_completed(SaveProgressService.TUTORIAL_CLIMB), "Departure input does not falsely complete kite quest")

	# Skip every optional town talk and leave; mark only on actual arrival.
	clear_scene()
	_seed_progress()
	town = await enter_scene(TOWN)
	town.player.position = town.right_gate_hint_anchor.position + Vector2(0, 42)
	await process_frame
	press_e()
	check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Pressing gate key alone cannot complete arrival")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == "res://scenes/story/comics/forest_entry_comic.tscn", "Departure plays new forest entry comic")
	check(not save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Comic does not prematurely record forest arrival")
	for i in 6:
		press_e()
		await create_timer(0.3).timeout
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == MIST and save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Can skip all NPCs and arrival records forest entry")
	check(log_service.get_track_view().is_empty(), "Finished first step disappears; unimplemented quests remain hidden")
	var persisted := ConfigFile.new()
	persisted.load(SaveProgressService.SAVE_PATH)
	check(persisted.get_value("progress", String(SaveProgressService.STORY_C1_FOREST_ENTERED), false), "Forest arrival persisted to disk")
	await capture("departure_forest_arrival")
	clear_scene()
	town = await enter_scene(TOWN)
	controller = town.get_node("Chapter1Departure")
	check(not controller.is_departure_active() and not town.right_gate_hint.task_guided, "Return town keeps gate open without replaying departure state")
	check(not save.has_completed(SaveProgressService.STORY_C1_TOWN_MAIDASHU), "Skipped conversations remain skipped, not marked by departure")
	print("CHAPTER 1 DEPARTURE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

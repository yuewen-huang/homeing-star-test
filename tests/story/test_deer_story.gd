extends "../support/harness.gd"

const FACTS := preload("res://scripts/story/forest_story_facts.gd")
const COLLECTION := preload("res://scripts/levels/lan_home/home_collection.gd")
const ROOM := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"


func run() -> void:
	var save := use_memory_progress()
	save.try_complete_facts([SaveProgressService.STORY_C1_DEER_DEFEATED, FACTS.AFTERMATH_PENDING,
		&"story_c1_deer_relic_presented"])
	save.claim_unique_reward(DeerStory.REWARD_ID, ItemCatalog.DEER_RELIC)
	check(change_scene_to_file(ROOM) == OK, "Load the official deer arena")
	await scene_changed
	await wait_frames(3)
	var arena := current_scene as Chapter1DeerBossRoom
	check(arena != null, "The official arena initialized")
	if arena == null:
		finish("DEER STORY AND REMATCH")
		return
	var story := arena.story
	check(story.comic == null and not paused and not arena.deer.visible and not arena.encounter.active,
		"A pending legacy aftermath cannot replay or revive the boss")
	check(story.chapter_gate.visible and arena._return_prompt.available and not arena.has_node("ForecourtTrace"),
		"Both routes reopen without the retired trail or resident")
	check(COLLECTION.COMICS.all(func(row): return row[0] not in ["林间远影", "林间的出口"]),
		"The storybook lists neither retired comic")

	press(KEY_E)
	await wait_frames(2)
	check(story.choices != null and paused, "E at the arena entrance opens the rematch menu directly")
	if story.choices == null:
		finish("DEER STORY AND REMATCH")
		return
	press(KEY_ESCAPE)
	await wait_frames(2)
	check(story.choices == null and not paused and not arena.player.input_frozen,
		"Cancelling the rematch prompt restores movement")
	press(KEY_E)
	press(KEY_1)
	for frame in 600:
		if current_scene != null and current_scene != arena \
				and not (root.get_node("SceneTransition") as SceneTransitionService).is_transitioning:
			break
		await process_frame
	var rematch := current_scene as Chapter1DeerBossRoom
	check(is_instance_valid(rematch) and rematch.story.is_rematch and rematch.encounter.active \
		and rematch.story.comic == null and not rematch.story.chapter_gate.visible,
		"The live rematch starts the first phase directly")
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 1 and save.has_completed(FACTS.AFTERMATH_PENDING) \
		and save.get_cinematic_status(FACTS.AFTERMATH_ID) == SaveProgressService.CinematicStatus.UNHANDLED,
		"The old facts remain intact and the unique relic is not duplicated")
	expect_save_untouched()
	finish("DEER STORY AND REMATCH")


func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

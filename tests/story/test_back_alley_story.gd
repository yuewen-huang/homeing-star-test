extends "../support/harness.gd"

const PROLOGUE := preload("res://scripts/story/prologue_dialogue.gd")
const STAGED_VIEW := preload("res://scripts/ui/main_story_dialogue.gd")
const COLLECTION := preload("res://scripts/levels/lan_home/home_collection.gd")
const ALLEY := "res://scenes/levels/back_alley/back_alley.tscn"
const COMIC := "res://scenes/story/comics/back_alley_pill_comic.tscn"
const TOWN := "res://scenes/levels/town/homeward_town.tscn"
const PILL := ItemCatalog.HANGOVER_PILL

func key_e() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func enter_scene(path: String) -> Node:
	var result := change_scene_to_file(path)
	assert(result == OK)
	await scene_changed
	return current_scene


func wait_for_route(transition: SceneTransitionService) -> void:
	var deadline := Time.get_ticks_msec() + 18000
	while transition.is_transitioning and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not transition.is_transitioning, "路由淡入完成")


func walk_to_master(alley: Node) -> void:
	alley.player.position = Vector2(alley.sleeping_master.position.x + 12.0, alley.FLOOR_Y)
	alley.camera_x = clampf(alley.player.position.x, alley.VIEW_WIDTH * 0.5,
		alley.world_length - alley.VIEW_WIDTH * 0.5)
	alley.update_scroll()


func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Capture " + label)


func verify_dialogue(dialogue: TutorialDialogue, part: String) -> bool:
	var opened := dialogue != null and dialogue is STAGED_VIEW and dialogue.opened
	check(opened, part + " uses the new dialogue")
	if not opened:
		return false
	var expected: Array = PROLOGUE.TEXT[part]
	check(dialogue._lines.size() == expected.size(), part + " has all original lines")
	for index in range(expected.size()):
		check(dialogue._lines[index]["text"] == expected[index]["text"], part + " keeps line %d" % (index + 1))
	for performer: Variant in dialogue._actors.values():
		check(performer.current.texture != null, part + " loads the staged portrait")
	return true


func run() -> void:
	var save := use_memory_progress()
	(root.get_node("QuestLog") as QuestLogService)._save = save
	for fact: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.TUTORIAL_CLIMB,
			SaveProgressService.STORY_EATING_TALK, SaveProgressService.STORY_MAGIC_SHOP_TALK,
			SaveProgressService.STORY_HANGOVER_PILL_EQUIPPED]:
		save.mark_completed(fact)
	save.add_item(PILL)
	check(save.equip_special_item(PILL), "Existing inventory equips the bead")
	var alley := await enter_scene(ALLEY)
	walk_to_master(alley)
	key_e()
	var dialogue := alley.get("master_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "alley_drunk"):
		finish("BACK ALLEY WAKE")
		return
	dialogue.advance()
	dialogue._complete_line()
	check(dialogue._actors[&"master"].current.texture.resource_path.ends_with("alley_drunk.png"),
		"Rayne is still holding the gourd when he mumbles")
	await capture("07-rayne-drunk")
	dialogue.advance()
	check(not alley.player.input_frozen and not save.has_completed(SaveProgressService.STORY_HANGOVER_PILL_USED_ON_MASTER),
		"The E scene returns control and leaves the bead available")

	Input.action_press(&"special_item_use")
	await physics_frame
	await process_frame
	Input.action_release(&"special_item_use")
	dialogue = alley.get("master_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "alley_give_pill"):
		finish("BACK ALLEY WAKE")
		return
	check(not save.has_completed(SaveProgressService.STORY_HANGOVER_PILL_USED_ON_MASTER),
		"Progress waits until Lan finishes the handoff line")
	dialogue.advance()
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	await wait_for_route(transition)
	check(current_scene.scene_file_path == COMIC, "Q hands off to the new comic")
	check(save.has_completed(SaveProgressService.STORY_HANGOVER_PILL_USED_ON_MASTER)
		and not save.has_completed(SaveProgressService.QUEST_BACK_ALLEY_STEP),
		"An unfinished comic still leaves the alley story pending")
	check(save.get_item_count(PILL) == 1 and save.get_equipped_special_item() == PILL,
		"The bead remains reusable and equipped for the existing combat")

	var reopened_alley := await enter_scene(ALLEY)
	walk_to_master(reopened_alley)
	key_e()
	await wait_for_route(transition)
	check(current_scene.scene_file_path == COMIC,
		"Restarting after the bead was used lets E return directly to the comic")
	var comic := current_scene as ComicPlayer
	if comic == null:
		finish("BACK ALLEY WAKE")
		return
	check(comic._frames.size() == 3, "Only the approved three wordless frames play")
	for index in comic._frames.size():
		check(comic.panel_index == index, "Frame %d is in reading order" % (index + 1))
		if index == 1:
			check(comic._image.texture.resource_path.ends_with("02_scabbard_traces.png"),
				"The scabbard residue is the middle frame")
			await capture("08-scabbard-traces")
		key_e()
		if index < comic._frames.size() - 1:
			await create_timer(0.26).timeout
	dialogue = comic.get("_wake_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "alley_sober"):
		finish("BACK ALLEY WAKE")
		return
	check(dialogue.layer > comic.layer and not comic.input_enabled,
		"The sober dialogue sits above the comic and owns its input")
	check(not save.has_completed(SaveProgressService.QUEST_BACK_ALLEY_STEP),
		"The final comic panel does not settle unread dialogue")
	dialogue._complete_line()
	await create_timer(0.22).timeout
	await capture("09-rayne-sober")
	while dialogue.opened:
		dialogue.advance()
	check(save.has_completed(SaveProgressService.QUEST_BACK_ALLEY_STEP)
		and save.has_completed(PROLOGUE.MASTER_WOKE_HEARD), "Both facts settle after the last spoken line")
	await wait_for_route(transition)
	check(current_scene.scene_file_path == TOWN, "Finished sequence returns to the main street")
	var before_replay := save.get_completed_tutorials()
	var gallery_index := COLLECTION.COMICS.find(["醒酒珠", COMIC])
	check(gallery_index >= 0 and COLLECTION.comic_panels(gallery_index).size() == 3,
		"Lan's storybook can replay the three replacement frames")
	check(save.get_completed_tutorials() == before_replay,
		"Reading gallery artwork does not settle any progress")
	expect_save_untouched()
	finish("BACK ALLEY WAKE")

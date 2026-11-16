extends "../support/harness.gd"

const PROLOGUE := preload("res://scripts/story/prologue_dialogue.gd")
const STAGED := preload("res://scripts/ui/main_story_dialogue.gd")
const COLLECTION := preload("res://scripts/levels/lan_home/home_collection.gd")
const TOWN := "res://scenes/levels/town/homeward_town.tscn"


func enter_town() -> Node:
	var result := change_scene_to_file(TOWN)
	assert(result == OK)
	await scene_changed
	(root.get_node("SceneTransition") as SceneTransitionService)._location_title.dismiss()
	return current_scene


func at_food_stall(town: Node) -> void:
	town.player.position = Vector2(town.MAIDASHU_X - 38.0, town.STREET_BASELINE)
	town.snap_camera_to_player()
	town._update_aberration_progression()


func press_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Capture " + label)


func run() -> void:
	var save := use_memory_progress()
	var quest_log := root.get_node("QuestLog") as QuestLogService
	quest_log._save = save
	for flag: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.TUTORIAL_CLIMB,
			SaveProgressService.STORY_EATING_TALK, SaveProgressService.QUEST_CHILD_KITE_PICKED,
			SaveProgressService.QUEST_ENTER_HALL, SaveProgressService.QUEST_FIRST_SIGHT_STEP,
			SaveProgressService.QUEST_LAN_AND_WIND_STEP, SaveProgressService.STORY_LAN_AND_WIND_TALK,
			SaveProgressService.STORY_MAGIC_SHOP_TALK, SaveProgressService.STORY_HANGOVER_PILL_EQUIPPED,
			SaveProgressService.STORY_BACK_ALLEY_ENTERED, SaveProgressService.QUEST_BACK_ALLEY_STEP,
			PROLOGUE.MASTER_WOKE_HEARD]:
		save.mark_completed(flag)
	quest_log._refresh()
	var town := await enter_town()
	var dusk: Node = town.dusk_story
	check(dusk != null and town.aberration_staff_event == null, "New dusk sequence opens before staff run")
	if dusk == null:
		finish("PROLOGUE DUSK")
		return
	check(is_equal_approx(town.town_night_material.get_shader_parameter(&"exposure"), 0.8),
		"Town starts in dusk lighting")
	town.player.position = Vector2(town.NAVIGATION_DOOR_X, town.STREET_BASELINE)
	town._update_aberration_progression()
	check(town.aberration_escape_comic == null, "The Hall escape cannot start before Rayne sends Lan")

	at_food_stall(town)
	check(dusk._speakers[0] is TownSilhouette and dusk._speakers[1] is TownSilhouette
		and dusk._speakers[2] == town.maidashu, "Two reusable silhouettes speak before Maida")
	check(town.player.input_frozen and dusk._bubble.visible, "The argument starts at the food stall")
	for index in PROLOGUE.DUSK_ARGUMENT.size():
		check(dusk._bubble._label.text == PROLOGUE.DUSK_ARGUMENT[index],
			"Argument bubble %d keeps its place and wording" % (index + 1))
		if index == 1:
			await capture("10-dusk-silhouettes")
		dusk._bubble_hold.custom_step(4.0)
	var comic := dusk._comic as ComicPlayer
	check(comic != null and comic._frames.size() == 3,
		"The exact three approved frames follow the argument")
	if comic == null:
		finish("PROLOGUE DUSK")
		return
	for index in comic._frames.size():
		check(comic.panel_index == index, "Dusk panel %d is in order" % (index + 1))
		if index == 1:
			check(comic._image.texture.resource_path.ends_with("02_blackout.png"),
				"The second frame shows the Hall beam and lamps out")
			await capture("11-dusk-blackout")
		if index < comic._frames.size() - 1:
			check(not save.has_completed(PROLOGUE.DUSK_BLACKOUT_SEEN),
				"Partially viewed art has not reached its world fact")
		press_e()
		if comic._changing_panel:
			comic._fade_tween.custom_step(0.5)
	check(save.has_completed(PROLOGUE.DUSK_BLACKOUT_SEEN) and
		not save.has_completed(SaveProgressService.STORY_ABERRATION_CALLOUTS_COMPLETE),
		"The comic records the blackout while the scene awaits Rayne's dialogue")
	check(is_equal_approx(town.town_night_material.get_shader_parameter(&"exposure"), 0.62),
		"The playable street darkens after the comic")

	town = await enter_town()
	dusk = town.dusk_story
	at_food_stall(town)
	var dialogue := dusk._dialogue as TutorialDialogue
	check(dialogue != null and dialogue is STAGED and dialogue.opened and dusk._comic == null,
		"Reloading after the blackout resumes at the new dialogue")
	if dialogue == null:
		finish("PROLOGUE DUSK")
		return
	var lines: Array = PROLOGUE.TEXT["dusk_guidance"]
	for index in lines.size():
		check(dialogue.get_line_progress().x == index and dialogue._label.text == lines[index]["text"],
			"Rayne and Lan keep the exact wording of line %d" % (index + 1))
		if index == 2:
			check(dialogue._actors[&"master"].current.texture.resource_path.ends_with("dusk_guides.png"),
				"Rayne turns toward Lan before advising her")
			dialogue._complete_line()
			await create_timer(0.22).timeout
			await capture("12-dusk-guidance")
		dialogue.advance()

	check(not town.player.input_frozen and town.aberration_staff_event != null,
		"Reading the final line returns control and lets the staff run")
	check(save.has_completed(PROLOGUE.DUSK_GUIDANCE_HEARD)
		and save.has_completed(SaveProgressService.STORY_ABERRATION_CALLOUTS_COMPLETE),
		"New instructions and the old door milestone settle together")
	town.player.position = Vector2(town.NAVIGATION_DOOR_X, town.STREET_BASELINE)
	town._update_aberration_progression()
	check(town.aberration_escape_comic != null, "The real Hall entrance reaches the next existing story")
	var save_before_replay := save.get_completed_tutorials()
	var gallery_index := COLLECTION.COMICS.find(["黄昏的归航镇", "res://scripts/story/comics/prologue_dusk_comic.gd"])
	check(gallery_index >= 0 and COLLECTION.comic_panels(gallery_index).size() == 3,
		"Three dusk panels are available from the storybook")
	check(save.get_completed_tutorials() == save_before_replay,
		"Gallery loading leaves progress alone")

	save._config.set_value(SaveProgressService.PROGRESS_SECTION, String(PROLOGUE.DUSK_BLACKOUT_SEEN), false)
	save._config.set_value(SaveProgressService.PROGRESS_SECTION, String(PROLOGUE.DUSK_GUIDANCE_HEARD), false)
	town = await enter_town()
	check(town.dusk_story == null, "An old save that already passed the street does not replay it")
	expect_save_untouched()
	finish("PROLOGUE DUSK")

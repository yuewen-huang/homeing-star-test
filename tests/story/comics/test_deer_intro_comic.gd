extends "../../support/harness.gd"
## Actual approved M09 art, entry gating, full-view persistence and repeat card.

class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing

const ROOM := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
const Facts := preload("res://scripts/story/forest_story_facts.gd")
const Dialogue := preload("res://scripts/story/chapter_1_deer_dialogue.gd")
var save: MemoryProgress
var room: Chapter1DeerBossRoom
var story: DeerStory
var boss: DeerDuelBoss:
	get: return room.deer
var output := ""


func run() -> void:
	save = use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	save.try_complete_fact(Facts.VINE_ALTAR_READ)
	await enter()
	check(story.comic != null and paused and not boss.is_physics_processing() and room.player.input_frozen, "First final-room entry pauses fight for approved comic")
	var comic := story.comic
	check(comic.panels.size() == 6 and comic.panel_index == 0, "First entry starts at frame one of six")
	check(comic.layer == 900 and comic._image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "M09 covers HUD with proportional artwork")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var track := transition.music_player.stream
	var playhead := transition.music_player.get_playback_position()
	transition.is_transitioning = true
	key()
	check(comic.panel_index == 0, "Portal fade input cannot skip first frame")
	transition.is_transitioning = false
	for i in 6:
		check(comic.panel_index == i and comic._image.texture == comic.panels[i], "Actual approved panel %d displays in order" % (i + 1))
		check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == 0 and not save.has_completed(SaveProgressService.STORY_C1_DEER_ENCOUNTERED), "Frame %d does not prematurely record viewing or fight" % (i + 1))
		await capture("m09_panel_%02d" % (i + 1))
		if i < 5:
			key(KEY_SPACE if i % 2 == 0 else KEY_ENTER)
			key()
			check(comic.panel_index == i + 1, "Fast repeated advance cannot skip a frame")
			await create_timer(0.26).timeout
	check(track != null and transition.music_player.stream == track and transition.music_player.playing,
		"Boss music remains active throughout the comic")
	if DisplayServer.get_name() != "headless":
		check(transition.music_player.get_playback_position() > playhead, "Boss music playhead advances during the comic")
	var battle_huds := boss.get_children().filter(func(child: Node): return child is CanvasLayer and child.visible)
	key()
	await process_frame
	check(paused and story.comic == null and not is_instance_valid(comic) and story.dialogue != null
		and story.dialogue._actors.has(&"deer") and story.dialogue._actors.has(&"lan"),
		"The comic closes before the arena shows the two dialogue portraits")
	check(not room.player.visible and not boss.visible and not battle_huds.is_empty()
		and battle_huds.all(func(hud: CanvasLayer): return not hud.visible),
		"The portraits replace the world actors and combat HUD during the dialogue")
	var lines: Array = Dialogue.PREBATTLE.duplicate()
	lines.append(Dialogue.LAN_RECOGNIZES_DEER)
	for words in lines:
		var dialogue := story.dialogue
		check(dialogue._label.text == words and not room.encounter.active, "Prebattle wording precedes live combat")
		var line_index := dialogue.get_line_progress().x
		key()
		await process_frame
		check(dialogue.get_line_progress().x == line_index and dialogue._label.visible_characters == words.length(),
			"First press finishes the current line")
		if words in [Dialogue.PREBATTLE[0], Dialogue.LAN_RECOGNIZES_DEER]:
			await capture("m09_prebattle_%d" % line_index)
		key()
		await process_frame
	check(not paused and story.comic == null and not room.player.input_frozen and boss.phase == 1 and boss.is_physics_processing(), "Full ending releases actual mist-phase fight")
	check(room.player.visible and boss.visible and battle_huds.all(func(hud: CanvasLayer): return hud.visible),
		"Combat restores the world actors and visible boss HUD")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.WATCHED, "Full reading records WATCHED only at end")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_ENCOUNTERED) and not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Actual fight start is separate from victory")
	room.restart_mist_phase()
	check(story.comic == null and not paused and boss.phase == 1, "In-room death retry starts mist without comic")
	clear_scene()
	await enter()
	check(story.comic != null and story.comic.panel_index == 5 and paused, "Re-entry after full viewing shows last frame only")
	await capture("m09_reentry_last_frame")
	transition.is_transitioning = true
	await create_timer(1.2).timeout
	key()
	check(story.comic != null and paused, "Repeat hold does not elapse during scene fade or input")
	transition.is_transitioning = false
	await create_timer(1.2).timeout
	check(story.comic == null and not paused and boss.is_physics_processing(), "Last-frame card auto-starts battle after one visible second")
	clear_scene()
	seed_progress()
	await enter()
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and boss.is_physics_processing() and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.SKIPPED, "First skip enters battle with distinct SKIPPED record")
	clear_scene()
	await enter()
	check(story.comic != null and story.comic.panel_index == 0, "Skipping does not qualify as a complete viewing on next entry")
	var failed := FailedSave.new()
	failed._loaded = true
	failed._config.parse(save._config.encode_to_text())
	story.comic.progress = failed
	story.comic.panel_fade_duration = 0
	for i in 6: key()
	check(paused and story.comic != null and story.comic._pending_completion_retry, "Later full-view save failure remains retryable before battle")
	check(not failed.has_completed(SaveProgressService.STORY_C1_DEER_INTRO_WATCHED), "Failed full-view save does not unlock short entry")
	failed.failing = false
	key()
	await process_frame
	check(paused and story.dialogue != null and failed.has_completed(SaveProgressService.STORY_C1_DEER_INTRO_WATCHED),
		"Later full-view retry commits completion before the battle dialogue")
	check(story.dialogue.get_line_progress().y == 3, "Early challengers hear the deer without an unread altar reference")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and room.encounter.active, "Skipping the prebattle text still starts the fight")
	check(failed.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.SKIPPED, "Original skip history is preserved after later full read")
	save._config.parse(failed._config.encode_to_text())
	failed.free()
	clear_scene()
	await enter()
	check(story.comic != null and story.comic.panel_index == 5, "Full viewing after prior skip enables persisted last-frame entry")
	clear_scene()
	await create_timer(1.2).timeout
	check(not paused, "Freeing short card leaves no delayed battle or stuck pause")
	seed_progress()
	# Old encounter facts alone must not invent a full viewing.
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_ENCOUNTERED)
	await enter()
	check(story.comic != null and story.comic.panel_index == 0, "Old save with fight but no viewing still receives full art")
	key()
	await create_timer(0.26).timeout
	clear_scene()
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == 0 and not paused, "Mid-comic teardown leaves viewing unhandled")
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	await enter()
	check(story.comic == null and story._settled and not boss.is_physics_processing(), "Victory re-entry keeps existing safe corpse flow")
	clear_scene()
	expect_save_untouched()
	finish("DEER INTRO COMIC")


func seed_progress() -> void:
	save._config = ConfigFile.new()


func clear_scene() -> void:
	if is_instance_valid(room):
		room.free()
	current_scene = null


func enter() -> void:
	room = load(ROOM).instantiate() as Chapter1DeerBossRoom
	root.add_child(room)
	current_scene = room
	story = room.story
	await wait_frames(2)


func key(code := KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func capture(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(filename + ".png")) == OK,
		"Captured " + filename)

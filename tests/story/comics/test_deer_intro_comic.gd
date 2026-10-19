extends "../test_deer_story.gd"
## Actual approved M09 art, entry gating, full-view persistence and repeat card.

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
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
	check(transition.music_player.stream == track and transition.music_player.get_playback_position() > playhead, "Boss BGM remains continuous throughout comic")
	key()
	await process_frame
	check(not paused and story.comic == null and not room.player.input_frozen and boss.phase == 1 and boss.is_physics_processing(), "Full ending releases actual mist-phase fight")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.WATCHED, "Full reading records WATCHED only at end")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_ENCOUNTERED) and not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Actual fight start is separate from victory")
	room.restart_mist_phase()
	check(story.comic == null and not paused and boss.phase == 1, "In-room death retry starts mist without comic")
	save.load_progress()
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
	save.load_progress()
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
	check(not paused and failed.has_completed(SaveProgressService.STORY_C1_DEER_INTRO_WATCHED), "Later full-view retry commits completion")
	check(failed.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.SKIPPED, "Original skip history is preserved after later full read")
	save._config.parse(failed._config.encode_to_text())
	check(save.save_progress(), "Later completion persists to disk")
	failed.free()
	save.load_progress()
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
	print("DEER INTRO COMIC: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

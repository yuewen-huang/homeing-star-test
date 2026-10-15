extends "test_forest_trail_story.gd"
## Actual approved M07 artwork exercised through its production map interaction.

const ART_NAMES := ["01_distant_back", "02_recognition", "03_backpack_glimmer", "04_calling", "05_losing_sight", "06_empty_branches"]
const ART_SIZES := [Vector2(998, 380), Vector2(485, 314), Vector2(493, 314), Vector2(605, 351), Vector2(372, 351), Vector2(998, 410)]

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	await enter(VINE)
	await approach()
	check(point.position == Vector2(1130, 1420), "M07 uses the authored mid-vine safe observation point")
	check(point._has_art and point.prompt.can_interact(), "Approved production panels enable local E without resident prerequisites")
	check(not point.prompt.task_guided, "Observation point adds no main quest guidance")
	check(room._portals.all(func(data: Dictionary): return data.prompt.available), "All region and boss exits remain independent")
	await capture("m07_observation_point")
	var music := root.get_node("SceneTransition") as SceneTransitionService
	var track := music.music_player.stream
	var playhead := music.music_player.get_playback_position()
	room.player.air_state = LanPlayer.AirState.FALLING
	key()
	check(point.comic == null, "Airborne approach cannot open M07")
	room.player.air_state = LanPlayer.AirState.GROUNDED
	var standing_at: Vector2 = room.player.global_position
	key()
	await process_frame
	check(point.comic != null and paused and room.player.input_frozen, "E opens actual art over paused map")
	var comic := point.comic as WindSightingComic
	check(comic.panel_index == 0 and comic.panels.size() == 6, "Opening E does not leak into advancing the first of six panels")
	check(comic.layer == 900 and comic._image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Reader covers HUD and preserves artwork proportions")
	check(comic._image.offset_bottom == -52, "Reading hints stay below artwork")
	for i in 6:
		check(comic.panel_index == i and comic._image.texture.resource_path.get_file().get_basename() == ART_NAMES[i], "Approved frame %d displayed in order" % (i + 1))
		check(comic._image.texture.get_size() == ART_SIZES[i], "Frame %d keeps lossless source dimensions" % (i + 1))
		check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Reading frame %d does not prematurely settle" % (i + 1))
		await capture("m07_panel_%02d" % (i + 1))
		if i < 5:
			key(KEY_SPACE if i % 2 == 0 else KEY_ENTER)
			key()
			check(comic.panel_index == i + 1, "Fast extra input during frame fade is ignored")
			await create_timer(0.27).timeout
	check(music.music_player.stream == track and music.music_player.playing and music.music_player.get_playback_position() > playhead, "Forest music keeps same stream and advances through paused comic")
	key()
	await process_frame
	check(not paused and not room.player.input_frozen and point.comic == null, "Natural ending restores gameplay")
	check(room.player.global_position.distance_to(standing_at) < 1 and current_scene == room, "Reader returns to same position and same scene")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.WATCHED, "Only final completion writes WATCHED")
	check(not save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN) and not save.has_completed(SaveProgressService.STORY_C1_YUPO_MET), "Comic does not invent mist trace or NPC conversations")
	save.load_progress()
	clear_scene()
	await enter(VINE)
	await approach()
	check(not point.prompt.available, "Watched M07 stays handled on map reload")
	clear_scene()
	seed_progress()
	await enter(VINE)
	await approach()
	key()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not room.player.input_frozen and point.comic == null, "Esc closes actual comic and restores gameplay")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.SKIPPED, "Actual comic skip remains distinct from witnessed story")
	save.load_progress()
	clear_scene()
	await enter(VINE)
	await approach()
	check(not point.prompt.available, "Skipped M07 stays handled on map reload")
	clear_scene()
	seed_progress()
	await enter(VINE)
	await approach()
	key()
	await process_frame
	key()
	await create_timer(0.27).timeout
	clear_scene()
	await process_frame
	check(not paused and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Actual mid-read interruption leaves M07 unhandled and releases pause")
	await enter(VINE)
	await approach()
	key()
	await process_frame
	check(point.comic.panel_index == 0, "Interrupted read restarts from first approved panel")
	clear_scene()
	print("WIND SIGHTING COMIC: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing
const MIST := "res://scenes/sideview/chapter_1_mist_room.tscn"
const VINE := "res://scenes/sideview/chapter_1_vine_room.tscn"
var save: SaveProgressService
var room: Node2D
var point: Node2D
var failures := 0
var checks := 0
var output := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func seed_progress() -> void:
	save._config = ConfigFile.new()
	save._loaded = true
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			save._config.set_value("progress", String(value), not (String(value).begins_with("story_c1_") or String(value).begins_with("quest_c1_")))
	save.progress_changed.emit()
func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null
func enter(path: String) -> void:
	room = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	point = room.get_node("StoryPoints/WindTrace" if path == MIST else "StoryPoints/WindSighting")
	await process_frame
	await process_frame
func key(code: Key = KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func approach() -> void:
	room.player.position = point.global_position + Vector2(-48, 0)
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	await create_timer(0.15).timeout
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)
func fixture_comic() -> PackedScene:
	# Test-only synthetic textures never enter production artwork or screenshots.
	var comic := WindSightingComic.new()
	for i in 2:
		var texture := GradientTexture2D.new()
		texture.gradient = Gradient.new()
		comic.panels.append(texture)
	comic.panel_fade_duration = 0
	var scene := PackedScene.new()
	scene.pack(comic)
	comic.free()
	return scene
func enable_fixture() -> void:
	point.comic_scene = fixture_comic()
	point.refresh_art_availability()

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	await enter(MIST)
	check(point.position == Vector2(1250, 555) and point.dialogue == null and not paused, "Trace rests on existing mist floor without forced dialogue")
	await approach()
	check(point.prompt.can_interact(), "Local E prompt is reachable beside fallen branch")
	await capture("wind_trace_before")
	room.player.air_state = LanPlayer.AirState.FALLING
	key()
	check(point.dialogue == null, "Airborne player cannot initiate inspection")
	room.player.air_state = LanPlayer.AirState.GROUNDED
	key()
	await process_frame
	check(point.dialogue != null and paused and room.player.input_frozen, "Inspection pauses dangerous map")
	check(point.dialogue._label.text == "是他……", "M03 uses the approved single line")
	await capture("wind_trace_dialogue")
	check(not save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN), "Opening inspection does not mark completion")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not room.player.input_frozen and not save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN), "Cancelled inspection remains available")
	key()
	await process_frame
	point.dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN) and not paused, "Read inspection commits independent trace fact")
	save.load_progress()
	check(save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN), "Trace fact reloads from disk")
	await process_frame
	check(not point.prompt.available, "Completed trace cannot repeatedly trigger")
	await capture("wind_trace_after")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.UNHANDLED, "Recognizing trace never invents a Wind sighting")
	check((root.get_node("QuestLog") as QuestLogService).get_track_view().is_empty(), "Trace creates no main guidance or automatic sidequest")
	# The actual new inspection feeds the existing message-delivery conversation.
	save.try_complete_fact(SaveProgressService.STORY_C1_YUPO_MET)
	save.try_complete_fact(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED)
	save.try_complete_fact(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD)
	room.player.position = room.yupo.position + Vector2(-45, 0)
	await create_timer(0.15).timeout
	key()
	await process_frame
	for i in 3: room.yupo.dialogue.advance()
	await capture("wind_trace_yupo_right")
	for i in 2: room.yupo.dialogue.advance()
	check(room.yupo.dialogue._label.text == "有点痕迹，还没见着。", "Actual M03 inspection supplies truthful trace-only answer at grandma")
	for i in 2: room.yupo.dialogue.advance()
	clear_scene()
	await enter(MIST)
	await approach()
	check(not point.prompt.available and point.dialogue == null, "Re-entry leaves trace settled without replay")
	var failed := FailedSave.new()
	failed._loaded = true
	point.save = failed
	key()
	await process_frame
	point.dialogue.advance()
	check(point.choices != null and not failed.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN), "Failed inspection save offers retry and rolls back")
	failed.failing = false
	key(KEY_1)
	await process_frame
	check(failed.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN) and not paused, "Inspection retry commits and restores controls")
	point.save = save
	failed.free()
	clear_scene()

	seed_progress()
	await enter(VINE)
	await approach()
	# Explicitly simulate an absent-art handoff now that production M07 is installed.
	var empty_comic := WindSightingComic.new()
	var empty_scene := PackedScene.new()
	empty_scene.pack(empty_comic)
	empty_comic.free()
	point.comic_scene = empty_scene
	point.refresh_art_availability()
	point._process(0.0)
	check(not point._has_art and not point.prompt.available, "Explicit missing-art fixture has no empty interaction prompt")
	key()
	await process_frame
	check(not paused and point.comic == null and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Missing comic does not freeze, replace story or mark viewed/skipped")
	check(room._portals.all(func(data: Dictionary): return data.prompt.available), "Missing comic never locks exits or boss")
	enable_fixture()
	await process_frame
	check(point.prompt.can_interact(), "Completed art handoff enables same local interaction")
	key()
	await process_frame
	check(paused and room.player.input_frozen and point.comic != null, "Optional comic pauses world only after explicit E")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Comic start never counts as watched")
	clear_scene()
	await process_frame
	check(not paused and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Interrupted comic teardown restores world without completion")
	await enter(VINE)
	enable_fixture()
	await approach()
	key()
	await process_frame
	point.comic.panel_fade_duration = 0
	key()
	await process_frame
	check(point.comic != null and point.comic.panel_index == 1 and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Intermediate frame does not settle watched state")
	key()
	await process_frame
	check(not paused and point.comic == null and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.WATCHED, "Natural ending records watched and returns to same room")
	check(not save.has_completed(SaveProgressService.STORY_C1_WIND_TRACE_SEEN), "Watching comic does not backfill mist inspection")
	await process_frame
	check(not point.prompt.available, "Watched comic cannot replay from same observation point")
	clear_scene()
	seed_progress()
	await enter(VINE)
	enable_fixture()
	await approach()
	key()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.SKIPPED, "Esc records skipped separately and releases control")
	save.load_progress()
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.SKIPPED, "Skip status persists to disk")
	clear_scene()
	await enter(VINE)
	enable_fixture()
	await approach()
	check(not point.prompt.available, "Skipped comic remains handled after re-entry")
	clear_scene()
	seed_progress()
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	await enter(VINE)
	enable_fixture()
	await approach()
	check(not point.prompt.available and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Post-deer visit suppresses missed sighting without pretending it was watched")
	check(room._portals.all(func(data: Dictionary): return data.prompt.available), "Post-deer suppression leaves map passages open")
	clear_scene()
	seed_progress()
	await enter(VINE)
	enable_fixture()
	await approach()
	failed = FailedSave.new()
	failed._loaded = true
	point.save = failed
	key()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(paused and point.comic != null and failed.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Failed skip stays uncommitted and keeps retryable reader")
	failed.failing = false
	key()
	await process_frame
	check(not paused and failed.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == SaveProgressService.CinematicStatus.SKIPPED, "E retry preserves original skip outcome")
	failed._config = ConfigFile.new()
	failed.failing = true
	key()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and point.comic == null and failed.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Can leave failed optional settlement without fabricated skip or input lock")
	point.save = save
	failed.free()
	clear_scene()
	print("FOREST TRAIL STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

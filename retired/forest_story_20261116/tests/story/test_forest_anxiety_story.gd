extends SceneTree
## New story facts, legacy saves and authored world-state changes.
const Facts := preload("res://scripts/story/forest_story_facts.gd")
const Aftermath := preload("res://scripts/story/comics/deer_aftermath_comic.gd")
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
const ROOT := "res://scenes/levels/chapter_1/chapter_1_root_room.tscn"
const WIND := "res://scenes/levels/chapter_1/chapter_1_wind_room.tscn"
const VINE := "res://scenes/levels/chapter_1/chapter_1_vine_room.tscn"
const DEER := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
class FailingSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing
var save: SaveProgressService
var room: Node2D
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func seed_progress(legacy := false) -> void:
	save._config = ConfigFile.new()
	save._loaded = true
	for value in save.get_script().get_script_constant_map().values():
		if value is StringName and String(value).begins_with("story_") or value is StringName and String(value).begins_with("tutorial_") or value is StringName and String(value).begins_with("quest_"):
			save._config.set_value("progress", String(value), legacy or not (String(value).begins_with("story_c1_") or String(value).begins_with("quest_c1_")))
	save.progress_changed.emit()

func clear() -> void:
	if is_instance_valid(room): room.free()
	room = null
	current_scene = null
	await process_frame

func enter(path: String) -> void:
	room = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame

func key(code := KEY_E) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)

func stand(at: Vector2) -> void:
	room.player.position = at
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	if room.has_method("_update_camera"): room._update_camera()
	await create_timer(0.15).timeout

func talk(npc: Node2D) -> void:
	await stand(npc.position + Vector2(-40,0))
	key()
	await process_frame

func finish(npc: Node) -> void:
	if npc.dialogue == null:
		check(false, "Expected dialogue")
		return
	var count: int = npc.dialogue.get_line_progress().y - npc.dialogue.get_line_progress().x
	for i in count: npc.dialogue.advance()

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func run() -> void:
	save = root.get_node("SaveProgress")
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var failed := FailingSave.new()
	failed._loaded = true
	check(not failed.try_complete_facts(Facts.aliases(Facts.DELIVERED)), "Failed multi-fact settlement reports failure")
	check(not failed.has_completed(Facts.DELIVERED) and not failed.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Failure rolls back new and legacy records together")
	failed.failing = false
	check(failed.try_complete_facts(Facts.aliases(Facts.DELIVERED)), "Retry settles original records")
	failed.free()

	seed_progress(true)
	await enter(MIST)
	check(not room.has_node("XiaosuiReunion") and not save.has_completed(Facts.REUNION), "Legacy delivery never fabricates new reunion")
	await talk(room.yupo)
	check(room.yupo.dialogue != null and room.yupo.dialogue._label.text == "你从里头来的？", "Old met flag cannot hide revised greeting")
	await capture("legacy_yupo_right")
	room.yupo.dialogue.advance()
	await capture("legacy_lan_left")
	finish(room.yupo)
	check(save.has_completed(Facts.YUPO), "Only completed revised greeting records observation")
	await clear()

	await enter(ROOT)
	check(room.get_node("OvertightenedPost").relaxed, "Old victory relaxes local rope but retains cracked post")
	await talk(room.ali)
	check(room.ali.dialogue != null, "Old completed quest still allows new root observation")
	room.ali.dialogue.advance()
	check(room.ali.dialogue._label.text.contains("现在停了"), "Post-victory first visit never claims roots are still pulling")
	await capture("root_after_victory")
	key(KEY_ESCAPE)
	await process_frame
	check(not save.has_completed(Facts.ALI), "Cancelling revised root observation is retryable")
	await clear()

	await enter(WIND)
	await talk(room.lingwei)
	check(not room.letter_bag.visible and room.lingwei.dialogue != null, "Legacy returned bag stays returned while new letters conversation remains available")
	await capture("letters_after_victory")
	finish(room.lingwei)
	await clear()

	await enter(VINE)
	check(room.xiaosui != null, "Old delivery alone leaves Xiaosui available for new return plan")
	await talk(room.xiaosui)
	finish(room.xiaosui)
	await talk(room.xiaosui)
	key(KEY_1)
	await process_frame
	finish(room.xiaosui)
	check(not save.has_completed(Facts.RETURN_PLAN), "Hearing proposal does not accept it")
	key(KEY_1)
	await process_frame
	check(save.has_completed(Facts.RETURN_PLAN) and not save.has_completed(Facts.DELIVERED), "Explicit choice accepts only real return plan")
	await capture("vine_after_victory")
	await clear()

	await enter(MIST)
	await talk(room.yupo)
	finish(room.yupo)
	check(save.has_completed(Facts.DELIVERED) and not room.has_node("XiaosuiReunion"), "Delivery commits without teleporting NPC into ongoing conversation")
	await clear()
	await enter(VINE)
	check(room.xiaosui == null and room.has_node("RejoinedRope"), "After return plan delivery only rope evidence remains in vine region")
	await clear()
	(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_position(Vector2(240,555))
	await enter(MIST)
	check(room.has_node("XiaosuiReunion") and not save.has_completed(Facts.REUNION), "Reunion loads without claiming player saw it from far away")
	await stand(Vector2(790,555))
	check(save.has_completed(Facts.REUNION), "Nearby observation records witnessed reunion")
	await capture("grandmother_reunion")
	await clear()

	# Existing victory has no pending new movie. The gallery can still show it.
	save.claim_unique_reward(DeerStory.REWARD_ID, ItemCatalog.DEER_RELIC)
	save.try_complete_fact(DeerStory.REWARD_PRESENTED_ID)
	await enter(DEER)
	check(room.story.comic == null and not paused, "Legacy victory never forces new aftermath")
	check(String(room.story._resident_lines()[1].text).contains("小穗都在"), "Resident answer uses witnessed reunion")
	check(room.get_node("ExitRoots").relaxed, "Victory opens visual root barrier")
	await stand(Vector2(1990,room.FLOOR_Y))
	await capture("deer_open_exit")
	var before := save._config.encode_to_text()
	var gallery := preload("res://scripts/levels/lan_home/home_collection.gd")
	var movie_index := -1
	for i in gallery.COMICS.size():
		if String(gallery.COMICS[i][1]).contains("deer_aftermath"): movie_index = i
	check(movie_index >= 0 and gallery.comic_panels(movie_index).size() == 4, "Gallery contains four approved aftermath panels")
	check(save._config.encode_to_text() == before, "Gallery inspection never changes progress")
	await clear()

	# Interrupted first-clear movie resumes only where a genuine victory queued it.
	seed_progress()
	save.try_complete_facts([SaveProgressService.STORY_C1_DEER_DEFEATED, Aftermath.PENDING])
	await enter(DEER)
	check(paused and room.story.comic != null and not save.has_claimed_reward(DeerStory.REWARD_ID), "Pending aftermath resumes after persisted victory before reward")
	for i in 4:
		room.story.comic._show_panel(i, false)
		await capture("aftermath_" + str(i+1))
	var music := (root.get_node("SceneTransition") as SceneTransitionService).current_music_path
	await clear()
	check(not paused and save.get_cinematic_status(Aftermath.ID) == SaveProgressService.CinematicStatus.UNHANDLED, "Interrupted movie restores pause without marking watched")
	await enter(DEER)
	var film: WindSightingComic = room.story.comic
	check(film != null and film.panel_index == 0, "Interrupted first-clear movie restarts")
	film._request_finish(false)
	await process_frame
	check(save.get_cinematic_status(Aftermath.ID) == SaveProgressService.CinematicStatus.WATCHED, "Completed aftermath records watched independently")
	check(room.story.reward_reveal != null and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Movie completion leads to exactly one relic")
	room.story.reward_reveal._finish_reveal()
	await process_frame
	check(room.story.chapter_gate.visible and not paused, "Reward reveal opens chapter exit")
	check((root.get_node("SceneTransition") as SceneTransitionService).current_music_path == music, "Aftermath does not restart or change BGM")
	check(not save.has_completed(Facts.YUPO) and not save.has_completed(Facts.REUNION), "Boss-only route invents no resident knowledge")
	check(String(room.story._resident_lines()[1].text).contains("没留意"), "Boss-only answer admits unknown whereabouts")
	await clear()

	# Comic failed save retains its outcome for retry, without claiming completion.
	seed_progress()
	var movie := load("res://scenes/story/comics/deer_aftermath_comic.tscn").instantiate() as WindSightingComic
	failed = FailingSave.new()
	failed._loaded = true
	movie.progress = failed
	root.add_child(movie)
	movie._request_finish(true)
	check(movie._pending_completion_retry and failed.get_cinematic_status(Aftermath.ID) == 0, "Failed skip is retryable and does not claim completion")
	failed.failing = false
	movie._request_finish(true)
	check(failed.get_cinematic_status(Aftermath.ID) == SaveProgressService.CinematicStatus.SKIPPED, "Retry keeps original skip outcome")
	movie.free()
	failed.free()
	print("FOREST ANXIETY STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree

const MIST := "res://scenes/sideview/chapter_1_mist_room.tscn"
var save: SaveProgressService
var room: Node
var npc: Node
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func finish_lines() -> void:
	var dialogue: TutorialDialogue = npc.dialogue
	if dialogue == null:
		check(false, "Expected live dialogue")
		return
	var count := dialogue.get_line_progress().y - dialogue.get_line_progress().x
	for i in count: dialogue.advance()

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func enter_mist() -> void:
	room = load(MIST).instantiate()
	root.add_child(room)
	current_scene = room
	npc = room.yupo
	await process_frame
	await process_frame

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var config := ConfigFile.new()
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			config.set_value("progress", String(value), not (String(value).begins_with("story_c1_") or String(value).begins_with("quest_c1_")))
	save._config = config
	save._loaded = true
	await enter_mist()
	check(npc != null and npc.position == Vector2(680, 555), "Approved squirrel NPC appears at west rest stop")
	check(not paused and npc.dialogue == null, "Entering map never forces a dialogue")
	var sprite: AnimatedSprite2D = npc.get_node("Idle")
	check(sprite.sprite_frames.get_frame_count(&"idle") == 4 and sprite.is_playing(), "Approved four-frame idle runs")
	check((sprite.position + Vector2(64, 152) * sprite.scale).length() < 0.01, "Approved feet anchor stays on map floor")
	room.player.position = npc.position + Vector2(-45, 0)
	await create_timer(0.1).timeout
	room._save.set_stele_state(room.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	room._combat_stele_requested(room.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	var enemy: MistParryEnemy = room.mist_enemies[0]
	enemy._spawn_wait = 2.0
	enemy._physics_process(0.5)
	check(enemy.state == MistAmbusher.State.HIDDEN and enemy._spawn_wait == 2.0, "Rest stop freezes spawn countdown instead of generating attacks")
	key(KEY_E)
	await process_frame
	check(paused and room.player.input_frozen and npc.dialogue != null, "E opens M02 and pauses whole map")
	if npc.dialogue == null:
		quit(1)
		return
	check(npc.dialogue.get_line_progress() == Vector2i(0, 10), "M02 contains ten original lines without action cutscene")
	await capture("yupo_intro_right")
	npc.dialogue.advance()
	await capture("yupo_intro_left")
	var wait := enemy._spawn_wait
	var position: Vector2 = room.player.position
	await create_timer(0.2, true).timeout
	check(enemy._spawn_wait == wait and room.player.position == position, "Danger clock and movement stay paused while reading")
	check(not save.has_completed(SaveProgressService.STORY_C1_YUPO_MET), "Unread intro not prematurely marked")
	# Escape midway is a real cancellation, and pairing restores pause/input.
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not room.player.input_frozen and npc.dialogue == null, "Esc closes dialogue and restores world")
	check(not save.has_completed(SaveProgressService.STORY_C1_YUPO_MET), "Cancelled intro can be heard again")
	await process_frame
	key(KEY_E)
	await process_frame
	finish_lines()
	check(save.has_completed(SaveProgressService.STORY_C1_YUPO_MET) and not paused, "Finishing intro records only meeting")
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Meeting does not automatically accept sidequest")
	await process_frame
	key(KEY_E)
	await process_frame
	check(npc.choices != null and paused, "Repeat E shows topics while hazards remain paused")
	await capture("yupo_topics")
	key(KEY_1)
	await process_frame
	finish_lines()
	check(npc.choices != null and not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Hearing request still awaits a deliberate answer")
	await capture("yupo_accept_or_defer")
	key(KEY_2)
	await process_frame
	finish_lines()
	check(not paused and not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Defer leaves quest unaccepted and controls restored")
	var log_service := root.get_node("QuestLog") as QuestLogService
	check(log_service.get_track_view().is_empty(), "Unaccepted optional quest stays off taskbar")

	# Gossip remains available, without granting knowledge or stele completion.
	for topic in [KEY_2, KEY_3]:
		await process_frame
		key(KEY_E)
		await process_frame
		key(topic)
		await process_frame
		check(npc.dialogue != null and npc.dialogue.get_line_progress().y == 4, "Four-line optional local gossip")
		finish_lines()
	check(save.get_stele_state(&"mist_puzzle_entry") == 0 and save.get_stele_state(&"mist_combat_01") == 0, "Gossip does not grant stele completion")

	await process_frame
	key(KEY_E)
	await process_frame
	key(KEY_1)
	await process_frame
	finish_lines()
	key(KEY_1)
	await process_frame
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Accept reply must finish before saving")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED) and not paused, "Completed accept reply saves sidequest")
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD), "Acceptance never fabricates granddaughter reply")
	var view := log_service.get_track_view()
	check(view.quests.is_empty() and view.side_quests.size() == 1 and view.side_quests[0].id == QuestCatalog.QUEST_C1_YU_MESSAGE, "Accepted quest appears separately as optional")
	await capture("yupo_sidequest")
	# Exploration facts cannot generate an automatic first-chapter objective.
	save._config.set_value("progress", String(SaveProgressService.STORY_C1_FOREST_ENTERED), false)
	view = log_service.get_track_view()
	check(view.quests.is_empty() and view.side_quests.size() == 1, "Only accepted sidequest shows even before forest entry fact")
	save._config.set_value("progress", String(SaveProgressService.STORY_C1_FOREST_ENTERED), true)
	save.save_progress()
	var persisted := ConfigFile.new()
	persisted.load(SaveProgressService.SAVE_PATH)
	check(persisted.get_value("progress", String(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), false), "Accepted sidequest persisted to disk")
	room.free()
	current_scene = null
	await enter_mist()
	room.player.position = npc.position + Vector2(-45, 0)
	await create_timer(0.1).timeout
	key(KEY_E)
	await process_frame
	check(npc.choices != null and npc.dialogue == null, "Reload never forces completed intro")
	key(KEY_1)
	await process_frame
	check(npc.dialogue != null and npc.dialogue._label.text == "问到小穗了吗？", "Pending sidequest reminder reflects only actual knowledge")
	# Destroying scene mid-dialogue restores global pause as well.
	room.free()
	current_scene = null
	await process_frame
	check(not paused, "Scene teardown cannot leave global tree paused")
	print("YUPO STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

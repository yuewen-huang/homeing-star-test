extends SceneTree

class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing

const WIND_ROOM := "res://scenes/sideview/chapter_1_wind_room.tscn"
var save: SaveProgressService
var room: Chapter1WindRoom
var npc: Node2D
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func seed_progress() -> void:
	var config := ConfigFile.new()
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			config.set_value("progress", String(value), not (String(value).begins_with("story_c1_") or String(value).begins_with("quest_c1_")))
	save._config = config
	save._loaded = true
	save.progress_changed.emit()

func key(code: Key = KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null

func enter_wind() -> void:
	room = load(WIND_ROOM).instantiate() as Chapter1WindRoom
	root.add_child(room)
	current_scene = room
	npc = room.lingwei
	await process_frame
	await process_frame

func stand_at(at: Vector2) -> void:
	room.player.position = at
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	room._update_camera()
	room.camera.reset_smoothing()
	room.camera.force_update_scroll()
	await create_timer(0.15).timeout

func talk() -> void:
	await stand_at(npc.position + Vector2(-50, 0))
	key()
	await process_frame

func pickup() -> void:
	await stand_at(room.letter_bag.global_position + Vector2(-35, 0))
	key()
	await process_frame

func finish_lines() -> void:
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
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	await enter_wind()
	check(npc.position == Vector2(1430, 1797) and not paused and npc.dialogue == null, "Lingwei waits inside existing WestRest without forced conversation")
	check(room.letter_bag.global_position == Vector2(700, 2500), "Bag rests on lower existing entrance branch outside first updraft")
	var sprite := npc.get_node("Idle") as AnimatedSprite2D
	check(sprite.sprite_frames.get_frame_count(&"idle") == 4 and sprite.is_playing(), "Approved rabbit four-frame idle plays")
	check((sprite.position + Vector2(64, 152) * sprite.scale).length() < 0.01, "Rabbit feet preserve authored anchor and scale")
	await stand_at(npc.position + Vector2(-50, 0))
	check(npc._bubble != null and npc._bubble.visible and not room.player.input_frozen, "Approach bubble leaves player free")
	await capture("lingwei_greeting")
	room.player.air_state = LanPlayer.AirState.FALLING
	key()
	check(npc.dialogue == null, "Cannot initiate dialogue while falling")
	room.player.air_state = LanPlayer.AirState.GROUNDED
	key()
	await process_frame
	check(npc.dialogue != null and paused and room.player.input_frozen, "Grounded E opens six-line intro and pauses map")
	if npc.dialogue == null:
		quit(1)
		return
	check(npc.dialogue.get_line_progress() == Vector2i(0, 6), "Greeting bubble is not duplicated in intro")
	await capture("lingwei_intro_left")
	npc.dialogue.advance()
	await capture("lingwei_intro_right")
	var moving := room.get_node("Terrain/CoreStep") as TerrainPiece
	var original := moving.position
	await create_timer(0.25, true).timeout
	check(moving.position == original, "Conversation pauses moving branch physics")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not room.player.input_frozen and not save.has_completed(SaveProgressService.STORY_C1_LINGWEI_MET), "Interrupted intro does not save meeting and restores control")
	await talk()
	finish_lines()
	check(save.has_completed(SaveProgressService.STORY_C1_LINGWEI_MET) and npc.choices != null, "Finished meeting offers optional help")
	key(KEY_2)
	await process_frame
	check(not paused and not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_ACCEPTED), "Declining leaves sidequest unaccepted")
	await talk()
	key(KEY_2)
	await process_frame
	check(npc.dialogue.get_line_progress().y == 4, "Friend question gives no direction or invented encounter")
	finish_lines()
	await talk()
	key(KEY_3)
	await process_frame
	check(npc.dialogue.get_line_progress().y == 4, "Unknown road stays unknown without proof of traversal")
	finish_lines()
	await talk()
	key(KEY_4)
	await process_frame
	npc.dialogue.advance()
	check(npc.dialogue._label.text == "没。我刚把信弄丢，哪还有心思。", "No minigame instructions or invented stele knowledge")
	finish_lines()
	await talk()
	key(KEY_1)
	await process_frame
	key(KEY_1)
	await process_frame
	check(npc.dialogue.get_line_progress().y == 5 and not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_ACCEPTED), "Acceptance waits until all five lines finish")
	for i in 4: npc.dialogue.advance()
	await capture("lingwei_request")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_ACCEPTED) and not paused, "Acceptance saved independently")
	var quests := root.get_node("QuestLog") as QuestLogService
	check(quests.get_track_view().quests.is_empty() and quests.get_track_view().side_quests.size() == 1, "Only accepted sidequest appears without main guidance")
	await pickup()
	check(npc.dialogue != null and room.letter_bag.visible and not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED), "Inspecting bag does not collect before reading completes")
	await capture("lingwei_bag_pickup")
	key(KEY_ESCAPE)
	await process_frame
	check(room.letter_bag.visible and not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED), "Cancelled pickup leaves bag available")
	await pickup()
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED) and not room.letter_bag.visible, "Committed pickup removes world prop")
	check(not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_RETURNED), "Pickup never claims handover")
	# Read back synchronously before visual awaits, avoiding other tools' save fixtures.
	save.load_progress()
	check(save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED), "Pickup survives disk reload")
	var inventory := save.get_inventory_items().duplicate(true)
	clear_scene()
	await enter_wind()
	check(not room.letter_bag.visible, "Re-entering cannot respawn a picked bag")
	await talk()
	check(npc.dialogue._label.text == "对，就是这个。让我数数。", "Accepted route goes directly to handover")
	key(KEY_ESCAPE)
	await process_frame
	check(not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_RETURNED), "Cancelled handover retains pending quest")
	await talk()
	for i in 4: npc.dialogue.advance()
	await capture("lingwei_handover_relief")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_RETURNED) and quests.get_track_view().is_empty(), "Finished handover completes sidequest")
	check(save.get_inventory_items() == inventory and room.puzzle.state == 0 and room.combat.state == 0, "No invented reward or stele completion")
	check(room._portals.all(func(data: Dictionary): return data.prompt.available), "Optional quest leaves all exits open")
	await talk()
	key(KEY_1)
	await process_frame
	check(npc.dialogue._label.text.begins_with("都齐了，我数完了。"), "Repeat thanks does not send player for another bag")
	finish_lines()
	await talk()
	key(KEY_4)
	await process_frame
	npc.dialogue.advance()
	check(npc.dialogue._label.text == "没。刚才光顾着数信了。", "Post-return gossip does not claim bag is still lost")
	finish_lines()
	clear_scene()

	# Reverse order: no acceptance/meeting required, and no invented prior facts.
	seed_progress()
	await enter_wind()
	await pickup()
	check(npc.dialogue._label.text == "一个小包，角上补过。", "Unprompted pickup does not pretend player already knows whose bag it is")
	finish_lines()
	await talk()
	check(npc.dialogue._label.text == "底下捡的，是你的？", "First encounter can hand over previously found bag")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_RETURNED) \
		and not save.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_ACCEPTED) \
		and not save.has_completed(SaveProgressService.STORY_C1_LINGWEI_MET), "Direct handover does not fabricate acceptance or earlier intro")
	clear_scene()

	seed_progress()
	(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_anchor(NodePath("Portals/VineGate"))
	await enter_wind()
	check(save.has_completed(SaveProgressService.STORY_C1_WIND_VINE_ARRIVED), "Actual vine entry records road knowledge independently")
	await talk()
	finish_lines()
	key(KEY_2)
	await process_frame
	await talk()
	key(KEY_3)
	await process_frame
	check(npc.dialogue._label.text == "我从那边过来的，能走。", "Player may report only a route actually traversed")
	finish_lines()

	# Failure rollback: the bag must remain until its fact has been saved.
	var failed := FailedSave.new()
	failed._loaded = true
	npc.save = failed
	await pickup()
	finish_lines()
	check(npc.choices != null and room.letter_bag.visible and not failed.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED), "Failed pickup save leaves bag and offers retry")
	key(KEY_2)
	await process_frame
	check(not paused and not room.player.input_frozen, "Leaving failed pickup restores map")
	await pickup()
	finish_lines()
	failed.failing = false
	key(KEY_1)
	await process_frame
	check(failed.has_completed(SaveProgressService.QUEST_C1_LETTER_BAG_PICKED) and not room.letter_bag.visible, "Successful retry commits original pickup and hides prop")
	npc.save = save
	failed.free()
	await talk()
	check(paused, "Dialogue opens before teardown check")
	clear_scene()
	await process_frame
	check(not paused, "Scene teardown restores global pause")
	print("LINGWEI STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing
const VINE := "res://scenes/levels/chapter_1/chapter_1_vine_room.tscn"
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
var save: SaveProgressService
var room: Node2D
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
func enter(path: String) -> void:
	room = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	npc = room.xiaosui if path == VINE else room.yupo
	await process_frame
	await process_frame
func talk() -> void:
	room.player.position = npc.position + Vector2(-45, 0)
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	await create_timer(0.15).timeout
	key()
	await process_frame
func topic(code: Key = KEY_1) -> void:
	await talk()
	key(code)
	await process_frame
func finish_lines() -> void:
	if npc.dialogue == null:
		check(false, "Expected live dialogue")
		return
	var count: int = npc.dialogue.get_line_progress().y - npc.dialogue.get_line_progress().x
	for i in count: npc.dialogue.advance()
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)
func take_message() -> void:
	await topic()
	finish_lines()
	key(KEY_1)
	await process_frame
func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_anchor(NodePath("Portals/WindGate"))
	await enter(VINE)
	check(npc.position == Vector2(580, 620) and npc.dialogue == null and not paused, "Wind entry places one optional Xiaosui on nearby existing safe branch")
	var sprite := npc.get_node("Idle") as AnimatedSprite2D
	check(sprite.sprite_frames.get_frame_count(&"idle") == 4 and sprite.is_playing(), "Approved squirrel idle plays")
	check((sprite.position + Vector2(64, 152) * sprite.scale).length() < 0.01, "Authored scale and foot anchor retained")
	save.load_progress()
	check(save.has_completed(SaveProgressService.STORY_C1_XIAOSUI_WIND_SPOT), "First meeting location persisted without talking")
	await talk()
	check(paused and room.player.input_frozen and npc.dialogue.get_line_progress().y == 6, "Active conversation pauses map with six-line intro")
	await capture("xiaosui_intro_left")
	npc.dialogue.advance()
	await capture("xiaosui_intro_right")
	var player_at: Vector2 = room.player.position
	await create_timer(0.2, true).timeout
	check(room.player.position == player_at and paused, "Reading holds player safely while world is paused")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not save.has_completed(SaveProgressService.STORY_C1_XIAOSUI_MET), "Cancelling intro does not claim meeting")
	await talk()
	finish_lines()
	check(save.has_completed(SaveProgressService.STORY_C1_XIAOSUI_MET) and not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD), "Meeting does not auto-carry message")
	await talk()
	check(npc.choices.options.size() == 5, "No deer topic without actual chase")
	key(KEY_2)
	await process_frame
	check(npc.dialogue.get_line_progress().y == 4, "Friend gossip stays local")
	finish_lines()
	await topic(KEY_3)
	check(npc.dialogue.get_line_progress().y == 4, "Vine gossip is personal experience only")
	finish_lines()
	await topic()
	check(npc.dialogue._label.text.begins_with("你要回镇上"), "Granddaughter-first proposal never claims grandma already asked")
	finish_lines()
	key(KEY_2)
	await process_frame
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD) and not paused, "Can decline carrying message")
	await take_message()
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD) and not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Granddaughter-first acceptance preserves separate grandma facts")
	var quests := root.get_node("QuestLog") as QuestLogService
	var view := quests.get_track_view()
	check(view.quests.is_empty() and view.side_quests.size() == 1, "Message accepted from either endpoint appears as optional quest")
	check(view.side_quests[0].current_text == "顺路回雾口时，把小穗的口信告诉榆婆", "Pending message targets grandma")
	await topic()
	check(npc.dialogue._label.text == "我一会儿就走，你回去碰见她再说。", "Undelivered reminder does not claim grandma knows")
	finish_lines()
	clear_scene()
	(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_anchor(NodePath("Portals/RootGate"))
	await enter(VINE)
	check(npc.position == Vector2(580, 620), "Entering later from other gate never duplicates or relocates Xiaosui")
	clear_scene()
	await enter(MIST)
	await talk()
	check(npc.dialogue._label.text == "你是榆婆？小穗让我带句话。", "First grandma encounter delivers directly without extra round trip")
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Delivery waits for completed dialogue")
	await capture("xiaosui_direct_delivery")
	key(KEY_ESCAPE)
	await process_frame
	check(not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Cancelled delivery can resume later")
	await talk()
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED) and not save.has_completed(SaveProgressService.STORY_C1_YUPO_MET), "Direct delivery records only real settlement, not unread intro")
	check(quests.get_track_view().is_empty(), "Delivered quest leaves taskbar")
	save.load_progress()
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Actual delivery persists to disk")
	clear_scene()

	# Grandma-first route uses the full reply and existing acceptance.
	seed_progress()
	save.try_complete_fact(SaveProgressService.STORY_C1_YUPO_MET)
	save.try_complete_fact(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED)
	(root.get_node("SceneTransition") as SceneTransitionService).set_scene_entry_anchor(NodePath("Portals/RootGate"))
	await enter(VINE)
	check(npc.position == Vector2(3940, 2320), "First root entry places Xiaosui near root-side safe branch")
	await talk()
	finish_lines()
	await topic()
	check(npc.dialogue._label.text == "榆婆让我问，你怎么还没回去。" and npc.dialogue.get_line_progress().y == 7, "Grandma-first route uses seven original message lines")
	await capture("xiaosui_message_from_grandma")
	finish_lines()
	key(KEY_1)
	await process_frame
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD), "Full reply plus deliberate choice commits message")
	await capture("xiaosui_return_objective")
	clear_scene()
	await enter(MIST)
	await talk()
	check(npc.dialogue.get_line_progress().y == 7, "Known grandma receives full delivery conversation")
	for i in 5: npc.dialogue.advance()
	check(npc.dialogue._label.text == "还没有。", "No trace or sighting yields truthful no-news answer")
	key(KEY_ESCAPE)
	await process_frame
	# Only genuine saved trace / watched-comic facts can change the search answer.
	save.try_complete_fact(SaveProgressService.STORY_C1_WIND_TRACE_SEEN)
	await talk()
	for i in 5: npc.dialogue.advance()
	check(npc.dialogue._label.text == "有点痕迹，还没见着。", "Trace-only answer does not pretend Wind was seen")
	key(KEY_ESCAPE)
	await process_frame
	save.finish_cinematic(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING, true)
	await talk()
	for i in 5: npc.dialogue.advance()
	check(npc.dialogue._label.text == "有点痕迹，还没见着。", "Skipped comic never counts as witnessing Wind")
	key(KEY_ESCAPE)
	await process_frame
	save._config.set_value("cinematics", String(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING), SaveProgressService.CinematicStatus.WATCHED)
	await talk()
	for i in 5: npc.dialogue.advance()
	check(npc.dialogue._label.text == "远远看见了，没追上。", "Watched sighting takes precedence over traces")
	await capture("xiaosui_delivery_news")
	key(KEY_ESCAPE)
	await process_frame
	var failed := FailedSave.new()
	failed._loaded = true
	failed._config.set_value("progress", String(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD), true)
	failed._config.set_value("progress", String(SaveProgressService.STORY_C1_YUPO_MET), true)
	npc.save = failed
	await talk()
	finish_lines()
	check(npc.choices != null and not failed.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Failed grandma settlement rolls back and offers retry")
	failed.failing = false
	key(KEY_1)
	await process_frame
	check(failed.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED) and not paused, "Delivery retry commits and restores map")
	npc.save = save
	failed.free()
	await talk()
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_DELIVERED), "Real grandma route finishes independently")
	clear_scene()
	await enter(VINE)
	check(npc.position == Vector2(3940, 2320), "Root-first placement remains stable across reloads")
	await topic()
	check(npc.dialogue._label.text == "话带到了。", "Repeat talk knows only player's actual delivery")
	finish_lines()
	check(room._portals.all(func(data: Dictionary): return data.prompt.available) and room.puzzle.state == 0 and room.combat.state == 0, "Story leaves four exits and both steles independent")
	clear_scene()

	# Real production rush, not entry or windup, records chase knowledge.
	seed_progress()
	var boss_room := load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	root.add_child(boss_room)
	current_scene = boss_room
	# The M09 intro comic (tested in test_deer_intro_comic) pauses the fight; skip it to reach real combat.
	if boss_room.story.comic != null: boss_room.story.comic._request_finish(true)
	await process_frame
	await process_frame
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_CHASE_SEEN), "Entering final room alone grants no chase knowledge")
	boss_room.deer.start_charge_at(boss_room.player.position.x)
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_CHASE_SEEN), "Charge windup alone grants no chase knowledge")
	await create_timer(1.2).timeout
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_CHASE_SEEN), "Actual production charging run records encounter")
	clear_scene()
	await enter(VINE)
	await talk()
	finish_lines()
	await talk()
	check(npc.choices.options.size() == 6, "Actual chase unlocks optional M08 report")
	key(KEY_5)
	await process_frame
	check(npc.dialogue.get_line_progress().y == 6 and npc.dialogue._label.text == "上头有只鹿。", "M08 is player-initiated and locally limited")
	finish_lines()
	check(save.has_completed(SaveProgressService.STORY_C1_XIAOSUI_DEER_TOLD), "Read report records only Xiaosui's knowledge")
	var message_failure := FailedSave.new()
	message_failure._loaded = true
	message_failure._config.set_value("progress", String(SaveProgressService.STORY_C1_XIAOSUI_MET), true)
	message_failure._config.set_value("progress", String(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), true)
	npc.save = message_failure
	await take_message()
	check(npc.choices != null and not message_failure.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD), "Failed carrying-message save offers retry without claiming reply")
	message_failure.failing = false
	key(KEY_1)
	await process_frame
	check(message_failure.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_HEARD) and not paused, "Message retry commits and releases control")
	npc.save = save
	message_failure.free()
	await talk()
	check(paused, "Topic menu owns pause before teardown")
	clear_scene()
	await process_frame
	check(not paused, "Scene teardown restores pause")
	print("XIAOSUI STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

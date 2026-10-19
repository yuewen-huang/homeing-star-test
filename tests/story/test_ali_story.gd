extends SceneTree

class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing

const ROOT_ROOM := "res://scenes/levels/chapter_1/chapter_1_root_room.tscn"
var save: SaveProgressService
var room: Chapter1RootRoom
var npc: Node2D
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func _seed_progress() -> void:
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

func enter_root() -> void:
	room = load(ROOT_ROOM).instantiate() as Chapter1RootRoom
	root.add_child(room)
	current_scene = room
	npc = room.ali
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

func finish_lines() -> void:
	var dialogue: TutorialDialogue = npc.dialogue
	if dialogue == null:
		check(false, "Expected dialogue")
		return
	var count := dialogue.get_line_progress().y - dialogue.get_line_progress().x
	for i in count: dialogue.advance()

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func talk() -> void:
	await stand_at(npc.position + Vector2(-35, 0))
	key()
	await process_frame

func low_water() -> void:
	room.water.snap_to_level(RootWater.LOW)
	for log: RootFloatLog in room._logs: log.snap_to_water()
	await process_frame
	await process_frame

func inspect() -> void:
	var log := room.get_node("Logs/LogWest") as RootFloatLog
	await stand_at(Vector2(log.position.x + 120, log.walk_y()))
	key()
	await process_frame

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	_seed_progress()
	await enter_root()
	check(npc.position == Vector2(1380, 1180) and npc.dialogue == null and not paused, "Mist arrival finds Ali beside puzzle stele without forcing dialogue")
	var sprite := npc.get_node("Idle") as AnimatedSprite2D
	check(sprite.sprite_frames.get_frame_count(&"idle") == 4 and sprite.is_playing(), "Approved four-frame beaver idle")
	check((sprite.position + Vector2(64, 152) * sprite.scale).length() < 0.01, "Authored feet anchor preserved")
	await stand_at(npc.position + Vector2(-35, 0))
	check(npc._bubble != null and npc._bubble.visible and not room.player.input_frozen, "Initial greeting is a nonblocking overhead bubble")
	await capture("ali_greeting")
	# Water may move during approach, but a conversation must pause its clock.
	room.water.request_level(RootWater.LOW)
	key()
	await process_frame
	check(npc.dialogue != null and paused and room.player.input_frozen, "E starts four-line M04 and pauses whole map")
	if npc.dialogue == null:
		quit(1)
		return
	check(npc.dialogue.get_line_progress() == Vector2i(0, 4), "Initial greeting is not duplicated in dialogue")
	await capture("ali_intro_left")
	npc.dialogue.advance()
	await capture("ali_intro_right")
	var surface := room.water.surface_y
	var delay := room.water._delay
	var log_rise: float = room.get_node("Logs/LogWest").rise
	await create_timer(0.25, true).timeout
	check(room.water.surface_y == surface and room.water._delay == delay \
		and room.get_node("Logs/LogWest").rise == log_rise, "Water delay, surface and floating log stay paused")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and not room.player.input_frozen and not save.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Cancel midway restores controls without claiming meeting completion")
	await talk()
	finish_lines()
	check(npc.choices != null and save.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Finished intro records meeting then offers optional help")
	key(KEY_2)
	await process_frame
	check(not paused and not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED), "Can decline without blocking exploration")

	# Optional local knowledge, with no automatic map or combat progress.
	await talk()
	key(KEY_2)
	await process_frame
	check(npc.dialogue != null and npc.dialogue.get_line_progress().y == 2, "Route answer describes only where Ali has been")
	finish_lines()
	await talk()
	key(KEY_3)
	await process_frame
	check(npc.dialogue != null and npc.dialogue.get_line_progress().y == 4, "East-winch gossip is optional and limited")
	finish_lines()
	await talk()
	key(KEY_1)
	await process_frame
	key(KEY_1)
	await process_frame
	check(npc.dialogue != null and not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED), "Selecting help still requires completing response")
	if npc.dialogue != null:
		for i in 2: npc.dialogue.advance()
		await capture("ali_request_long_line")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED) and not paused, "Completed acceptance saved independently")
	var log_service := root.get_node("QuestLog") as QuestLogService
	check(log_service.get_track_view().quests.is_empty() and log_service.get_track_view().side_quests.size() == 1, "Only voluntarily accepted sidequest appears")

	room.water.snap_to_level(RootWater.MID)
	for log: RootFloatLog in room._logs: log.snap_to_water()
	await process_frame
	check(not npc.inspect_prompt.available, "Clasp cannot be inspected at middle water")
	# Use the real west-shore winch, not quest code, to lower water.
	await stand_at(Vector2(1500, 1180))
	key()
	await process_frame
	check(room.water.is_moving() and room.water.target_level == RootWater.LOW, "Existing winch interaction lowers water normally")
	await create_timer(7.2).timeout
	check(room.water.level == RootWater.LOW and not room.water.is_moving(), "Water reaches low level under unchanged timing")
	await inspect()
	check(npc.dialogue != null and paused, "Standing on nearest log can inspect the actual visible clasp")
	await capture("ali_clasp_inspection")
	check(not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_CHECKED), "Inspection not marked before reading finishes")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_CHECKED) \
		and not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_REPORTED), "Inspection and report remain separate facts")
	await capture("ali_report_objective")
	var before_inventory := save.get_inventory_items().duplicate(true)
	var before_level := room.water.level
	await talk()
	check(npc.dialogue != null and npc.dialogue._label.text == "没卡住，扣环磨亮了。", "Returning after inspection starts actual report")
	if npc.dialogue != null:
		for i in 3: npc.dialogue.advance()
		await capture("ali_report_relief")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_REPORTED) and log_service.get_track_view().is_empty(), "Report completes this sidequest and removes it from taskbar")
	check(room.water.level == before_level and save.get_inventory_items() == before_inventory, "Report does not change water or invent rewards")
	check(save.get_stele_state(Chapter1RootRoom.PUZZLE_ID) == 0 and save.get_stele_state(Chapter1RootRoom.COMBAT_ID) == 0, "Talking does not complete either regional stele")
	check(room._portals.all(func(data: Dictionary): return data.prompt.available), "Optional quest never locks root-region exits")
	await talk()
	key(KEY_1)
	await process_frame
	check(npc.dialogue != null and npc.dialogue._label.text == "我还没下去呢，别急。", "Repeat talk does not falsely claim repairs finished")
	finish_lines()
	check(save.get_inventory_items() == before_inventory, "Repeating completion cannot issue duplicate rewards")
	await stand_at(Vector2(640, 640))
	var beaver_position := npc.position
	room.water.snap_to_level(RootWater.HIGH)
	await process_frame
	check(npc.position == beaver_position and npc.visible and not npc.prompt.can_interact(), "Beaver stays beside submerged stele; distant player cannot interact")
	check(not npc.inspect_prompt.available, "High water hides inspection interaction")

	# Unordered route: inspect before ever meeting Ali, then reload and report directly.
	clear_scene()
	_seed_progress()
	await enter_root()
	await low_water()
	await inspect()
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_CHECKED) \
		and not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED) \
		and not save.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Can inspect before accepting or meeting NPC")
	clear_scene()
	save.load_progress()
	await enter_root()
	await talk()
	check(npc.dialogue != null and npc.dialogue._label.text == "下面那个扣环磨亮了。", "Saved prior inspection allows direct report on first meeting")
	finish_lines()
	check(save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_REPORTED) \
		and not save.has_completed(SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED), "Direct report does not fabricate earlier acceptance")
	var persisted := ConfigFile.new()
	persisted.load(SaveProgressService.SAVE_PATH)
	check(persisted.get_value("progress", String(SaveProgressService.QUEST_C1_WEST_ROPE_REPORTED), false), "Actual report persisted to disk")

	# Fault injection: failed critical write must offer retry and restore world on leaving.
	var failed := FailedSave.new()
	failed._loaded = true
	npc.save = failed
	await talk()
	finish_lines()
	check(npc.choices != null and not failed.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Failed save stays uncommitted and offers retry")
	key(KEY_2)
	await process_frame
	check(not paused and not room.player.input_frozen, "Leaving failed settlement restores world")
	await talk()
	finish_lines()
	failed.failing = false
	key(KEY_1)
	await process_frame
	check(failed.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Retry saves the original fact successfully")
	key(KEY_2)
	await process_frame
	npc.save = save
	failed.free()
	await talk()
	check(paused, "Repeat topic menu pauses safely")
	clear_scene()
	await process_frame
	check(not paused, "Leaving map during conversation restores global pause")
	# First visit is recorded even when the player skips Ali entirely.
	_seed_progress()
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	transition.set_scene_entry_anchor(NodePath("Portals/VineGate"))
	await enter_root()
	check(npc.position == Vector2(4040, 560), "First vine arrival finds Ali beside upper-right winch")
	check(save.has_completed(SaveProgressService.STORY_C1_ROOT_ENTERED) and not save.has_completed(SaveProgressService.STORY_C1_ALI_MET), "Arrival persists without requiring conversation")
	# Reload before visual awaits: other workspace test runs also use this save path.
	save.load_progress()
	check(save.has_completed(SaveProgressService.STORY_C1_ROOT_ENTERED), "Root arrival fact reloads from disk")
	await stand_at(npc.position + Vector2(35, 0))
	check(npc.prompt.can_interact(), "Upper-right mechanism placement is reachable and interactable")
	await capture("ali_first_vine_entry")
	clear_scene()
	transition.set_scene_entry_anchor(NodePath("Portals/VineGate"))
	await enter_root()
	check(npc.position == Vector2(1380, 1180), "Reloaded return from vine puts Ali permanently beside puzzle stele")
	clear_scene()
	transition.set_scene_entry_anchor(NodePath("Portals/MistGate"))
	await enter_root()
	check(npc.position == Vector2(1380, 1180), "Later mist arrival also keeps the stele placement")
	clear_scene()
	_seed_progress()
	transition.set_scene_entry_anchor(NodePath("Portals/MistGate"))
	await enter_root()
	check(npc.position == Vector2(1380, 1180), "Explicit first mist entry uses puzzle stele")
	clear_scene()
	_seed_progress()
	transition.set_scene_entry_position(Vector2(2440, 560))
	await enter_root()
	check(npc.position == Vector2(4040, 560), "Legacy vine spawn preserves first-entry placement")
	await talk()
	finish_lines()
	key(KEY_1)
	await process_frame
	for i in 4: npc.dialogue.advance()
	check(npc.dialogue._label.text == "西岸下面，靠岸那根，绳上有个旧扣环。", "Upper-gallery request points to west shore instead of nearest log")
	await capture("ali_upper_request")
	finish_lines()
	await talk()
	key(KEY_3)
	await process_frame
	check(npc.dialogue._label.text == "你也管这边？", "Upper-gallery winch topic reflects present location")
	finish_lines()
	clear_scene()
	print("ALI STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

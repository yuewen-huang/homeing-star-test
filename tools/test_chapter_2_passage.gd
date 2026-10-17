extends SceneTree

class MemorySave extends SaveProgressService:
	var fail_write := false
	var disk := ""
	func load_progress() -> void:
		_config = ConfigFile.new()
		if not disk.is_empty(): _config.parse(disk)
		_loaded = true
	func save_progress() -> bool:
		if fail_write: return false
		disk = _config.encode_to_text()
		return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var save: MemorySave
var room: Chapter1DeerBossRoom
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null
func enter() -> void:
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame; await process_frame
func close_reward() -> void:
	if room.story.reward_reveal != null: room.story.reward_reveal._finish_reveal()
	await process_frame; await process_frame
func key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)
func wait_transition() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in 600:
		await process_frame
		if not transition.is_transitioning: return
	check(false, "Scene transition completes within 600 frames")

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save)
	real_save.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	# Legacy completed save: no optional quests, steles, reward or presentation records.
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	save.fail_write = true
	await enter()
	check(room.story.reward_pending and not room.story.chapter_gate.visible, "Failed reward save keeps portal locked")
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 0 and not save.has_claimed_reward(DeerStory.REWARD_ID), "Failed grant rolls back item and claim together")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and not paused, "Reward failure retains victory and player control")
	save.fail_write = false
	room.player.position = room.deer.position + Vector2(-60, 0)
	room.player.set_physics_process(false)
	room.story._process(0)
	key()
	await process_frame
	check(room.story.reward_reveal != null and paused and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Body interaction retries unique reward with existing item reveal")
	await capture("chapter2_relic_reward")
	# Closing during a write failure must be retryable without awarding another item.
	save.fail_write = true
	await close_reward()
	check(room.story.reward_pending and not room.story.chapter_gate.visible and not paused, "Presentation write failure leaves safe retry and hidden portal")
	save.fail_write = false
	room.story._settle_reward()
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Presentation retry never duplicates reward")
	# Quit while the reveal is open; re-entry offers it again from saved ownership.
	clear_scene()
	check(not paused, "Interrupted reveal restores scene pause")
	save.load_progress()
	await enter()
	check(room.story.reward_reveal != null and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Reload after interruption resumes reveal without a second grant")
	await close_reward()
	check(room.story.chapter_gate.visible and save.has_completed(DeerStory.REWARD_PRESENTED_ID), "Completed reveal persists and opens portal")
	check(not save.equip_special_item(ItemCatalog.DEER_RELIC), "Placeholder quest relic cannot accidentally occupy the Q combat slot")
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED) \
		and not save.has_completed(SaveProgressService.STORY_C1_FORECOURT_TRACE_SEEN), "Chapter access requires no corpse or trace inspection")
	clear_scene()
	save.load_progress()
	await enter()
	check(room.story.reward_reveal == null and room.story.chapter_gate.visible and not paused, "Completed save restores portal without replaying reward")
	check(save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Repeated room entry retains exactly one relic")
	room.player.set_physics_process(false)
	room.player.position = room.story.chapter_gate.position
	room._process(0)
	room.story._process(0)
	(room.get_node("Camera2D") as Camera2D).reset_smoothing()
	await capture("chapter2_gate_unlocked")
	key()
	await wait_transition()
	check(current_scene is SaltFieldPrototype, "Actual E interaction transitions into the salt field prototype")
	if current_scene is SaltFieldPrototype:
		var chapter := current_scene as SaltFieldPrototype
		await physics_frame; await physics_frame
		check(chapter.feet.distance_to(SaltFieldPrototype.SPAWN) < 2, "Salt field spawns the planar pawn at its entrance")
		await capture("chapter2_salt_field")
		chapter.set_physics_process(false)
		chapter.feet = SaltFieldPrototype.RETURN_POINT
		chapter._sync_view(0)
		key()
		await wait_transition()
		check(current_scene is Chapter1DeerBossRoom, "Return portal transitions back to the first chapter")
		if current_scene is Chapter1DeerBossRoom:
			room = current_scene as Chapter1DeerBossRoom
			check(room.player.position.distance_to(DeerStory.CHAPTER_2_GATE_POSITION) < 2 \
				and room.story.chapter_gate.visible and room.story.reward_reveal == null, "Return arrives beside chapter gate with victory and reward retained")
	clear_scene()
	print("CHAPTER 2 PASSAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

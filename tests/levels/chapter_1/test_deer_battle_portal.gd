extends SceneTree
## Real room/death signal/scene travel, with all progress isolated in memory.
class MemoryProgress extends SaveProgressService:
	var fail_writes := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_writes
	func is_ability_unlocked(_ability: StringName) -> bool: return true

const ROOM := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
var save: MemoryProgress
var transition: SceneTransitionService
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label_)

func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null

func enter_deer() -> Chapter1DeerBossRoom:
	clear_scene()
	var room := load(ROOM).instantiate() as Chapter1DeerBossRoom
	# No comic art is required to test the real battle-start hook.
	var comic := load("res://scripts/story/comics/deer_intro_comic.gd").new() as WindSightingComic
	var packed := PackedScene.new()
	packed.pack(comic)
	comic.free()
	room.deer_intro_scene = packed
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	room.player.combat_stats.refill_health_on_depletion = false
	room.deer.set_physics_process(false)
	return room

func fail_challenge(room: Chapter1DeerBossRoom, label_: String) -> void:
	room.player.combat_stats.apply_health_damage(room.player.combat_stats.max_health)
	check(room._returning_after_defeat and room.player.input_frozen and not room.deer.is_physics_processing(), label_ + ": death freezes the failed encounter")
	await process_frame
	var started := Time.get_ticks_msec()
	while transition.is_transitioning and Time.get_ticks_msec() - started < 10000:
		await process_frame
	check(not transition.is_transitioning and current_scene.scene_file_path == "res://scenes/levels/chapter_1/chapter_1_vine_room.tscn", label_ + ": defeat returns to the exterior vine map")
	if current_scene is Chapter1VineRoom:
		var player := current_scene.get_node("Lan") as LanPlayer
		player.set_physics_process(false)
		var portal := current_scene.get_node("Portals/HeartGate") as Node2D
		check(player.global_position.distance_to(portal.global_position) < 6 and player.combat_stats.health > 0 and not player.input_frozen, label_ + ": living player arrives at the actual outside portal")
		check(transition.current_music_path == Chapter1Music.FOREST.resource_path, label_ + ": forest music resumes")

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	save = MemoryProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	transition = root.get_node("SceneTransition") as SceneTransitionService
	Engine.time_scale = 8
	var room := enter_deer()
	check(not room.get_node("ReturnGate").visible and not room._return_prompt.available, "Battle start hides portal, caption and E prompt")
	room.player.position = room.get_node("ReturnGate").position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	room._unhandled_input(key)
	check(not room._return_prompt.can_interact() and not transition.is_transitioning, "Hidden portal cannot be used to escape combat")
	for phase in [1, 2, 3, 4]: room._on_phase_completed(phase)
	check(not room.get_node("ReturnGate").visible, "Phase signals without a completed final human defeat do not reopen the portal")
	await fail_challenge(room, "First challenge")
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Failed challenge does not grant victory")
	room = enter_deer()
	# Final settlement conditions are the same ones the production landing emits.
	room.deer.phase = 4
	room.deer.vine_phase.human = true
	room.deer.phase_transition._human_defeat = true
	room.deer.state = DeerBoss.State.COMPLETE
	save.fail_writes = true
	room.deer.phase_completed.emit(4)
	check(room.get_node("ReturnGate").visible and room._return_prompt.available and room.story.victory_pending, "Final defeat reopens the return portal even if victory persistence must be retried")
	save.fail_writes = false
	save._config.set_value("progress", String(DeerStory.REWARD_PRESENTED_ID), true)
	room.story._settle_victory()
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Retry persists the separate victory fact")
	room = enter_deer()
	await process_frame
	check(room.story._settled and room.get_node("ReturnGate").visible and room._return_prompt.available, "Re-entering after victory restores the return portal")
	transition.deer_rematch_requested = true
	room = enter_deer()
	check(room.story.is_rematch and not room.get_node("ReturnGate").visible and not room._return_prompt.available, "Rematch start hides the return portal despite a saved victory")
	await fail_challenge(room, "Rematch")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Failed rematch preserves the original victory")
	clear_scene()
	var regional := load("res://scenes/levels/chapter_1/chapter_1_wind_boss_room.tscn").instantiate() as Chapter1BossRoom
	root.add_child(regional)
	current_scene = regional
	regional.player.combat_stats.refill_health_on_depletion = false
	regional.player.combat_stats.apply_health_damage(regional.player.combat_stats.max_health)
	await process_frame
	check(current_scene == regional and regional.player.combat_stats.health > 0 and regional._return_prompt.available and not transition.is_transitioning, "Other BOSS rooms retain in-room revival and their available return portal")
	clear_scene()
	Engine.time_scale = 1
	await process_frame
	await process_frame
	await create_timer(0.3, true, false, true).timeout
	check(saved == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Checks leave the user's save byte-for-byte unchanged")
	print("DEER BATTLE PORTAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree

class TestProgress extends SaveProgressService:
	var writes_fail := false
	var disk_snapshot := ""
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		if writes_fail:
			return false
		disk_snapshot = _config.encode_to_text()
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var room: Chapter1WindRoom
var save: TestProgress
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	room._update_camera()
	room.camera.reset_smoothing()
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(filename + ".png"))

func load_room() -> void:
	room = load("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames()
	# Drive actual movement deterministically, without an accelerated frame clock.
	room.player.set_physics_process(false)
	room._stele_shortcut.set_physics_process(false)

func tick() -> void:
	await physics_frame
	room._stele_shortcut._physics_process(1.0 / 60.0)
	room.player._physics_process(1.0 / 60.0)

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	await load_room()
	var shortcut := room._stele_shortcut
	check(not shortcut.enabled and not shortcut.visible, "Incomplete puzzle hides and disables shortcut")
	save.set_stele_state(Chapter1WindRoom.PUZZLE_ID, MinigameStele.SteleState.UNLOCKED)
	check(not shortcut.enabled, "Unlocking the stele alone grants no shortcut")
	save.writes_fail = true
	check(not save.record_stele_minigame_result(Chapter1WindRoom.PUZZLE_ID, 1234, true), "Failed completion save is rejected")
	check(not shortcut.enabled, "Failed save does not activate shortcut")
	save.writes_fail = false
	check(save.record_stele_minigame_result(Chapter1WindRoom.PUZZLE_ID, 1234, true), "Retry commits puzzle completion")
	check(shortcut.enabled and shortcut.visible, "Successful completion immediately reveals and activates current")
	shortcut.set_physics_process(false)
	check(save.get_stele_state(Chapter1WindRoom.COMBAT_ID) == 0, "Shortcut requires no combat unlock")
	room.player.reset_after_map_fall(room.puzzle.to_global(room.puzzle.checkpoint_offset))
	for i in 30:
		await tick()
	check(absf(room.player.position.x - 468) < 2 and absf(room.player.position.y - 364) < 5, "Current leaves the puzzle checkpoint and interaction area at rest")
	room.player.reset_after_map_fall(shortcut.route[0])
	await capture("shortcut_launch")
	var health := room.player.combat_stats.health
	for i in 90:
		await tick()
	check(room.player.position.x > 1300 and room.player.position.y < 500, "Ordinary wind physics carries an idle player through the elevated channel")
	await capture("shortcut_midflight")
	for i in 210:
		await tick()
	var arena := room.get_node("Terrain/Arena") as TerrainPiece
	check(room.player.position.x >= arena.position.x and room.player.position.x < arena.position.x + arena._walk_length(), "Player arrives inside combat platform's horizontal bounds")
	check(absf(room.player.position.y - arena.position.y) < 4 and room.player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING], "Player exits current and lands safely on the combat platform")
	check(room.player.combat_stats.health == health and not room.combat_active, "Travel causes no damage and starts no combat")
	await capture("shortcut_arrival")
	# A later failed replay and unrelated updates cannot revoke a completed stele.
	save.record_stele_minigame_result(Chapter1WindRoom.PUZZLE_ID, 10, false)
	check(shortcut.enabled, "Failed puzzle replay preserves shortcut")
	var snapshot := save.disk_snapshot
	root.remove_child(room)
	room.free()
	# Restore only serialized progress to model returning after a game restart.
	save._config = ConfigFile.new()
	save._config.parse(snapshot)
	await load_room()
	check(room._stele_shortcut.enabled and room._stele_shortcut.visible, "Serialized puzzle completion restores shortcut on fresh room entry")
	room.player.reset_after_map_fall(room._stele_shortcut.route[0])
	for i in 300:
		await tick()
	check(absf(room.player.position.y - room.get_node("Terrain/Arena").position.y) < 4, "Restored current remains usable")
	print("WIND SHORTCUT CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

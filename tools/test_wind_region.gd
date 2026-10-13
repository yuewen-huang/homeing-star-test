extends SceneTree

## Window integration regression. All progress is held in memory.
class TestProgress extends SaveProgressService:
	var disk_snapshot := ""
	var writes_fail := false
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

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	Input.parse_input_event(event)
	await frames(2)

func capture(filename: String) -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--visual-dir")
	if index < 0:
		return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[index+1].path_join(filename))

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	room = load("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames(30)
	check(is_instance_valid(room.player), "New layout starts")
	check(ResourceLoader.exists(Chapter1WindRoom.HEART_SCENE), "Core room is available before puzzle completion")
	room.player.set_physics_process(false)
	for piece in room._checkpoints:
		room.player.reset_after_map_fall(piece.position+Vector2(100,0))
		await frames()
		var expected := piece.to_global(piece.get_meta("checkpoint_offset",Vector2(80,0)))
		check(room._checkpoint.is_equal_approx(expected), "%s checkpoint follows actual platform" % piece.name)
		room.player.position.y = room.world_size.y+100
		await frames(1)
		check(room.player.position.is_equal_approx(expected), "%s fall returns to its own platform" % piece.name)
	room.player.reset_after_map_fall(room.puzzle.position)
	await frames()
	await key(KEY_E)
	check(room.puzzle.state == MinigameStele.SteleState.UNLOCKED, "First E unlocks puzzle")
	check(not is_instance_valid(room._puzzle_game), "Unlock does not open window")
	await frames(10)
	check(room.puzzle.state != MinigameStele.SteleState.COMPLETED, "No empty-bell auto completion")
	await key(KEY_E)
	check(is_instance_valid(room._puzzle_game) and paused, "Second E opens paused window")
	var game := room._puzzle_game
	var origin := room.player.position
	var moving := room.get_node("Terrain/ReturnFork") as TerrainPiece
	var moving_origin := moving.position
	await frames(20)
	check(room.player.position == origin and moving.position == moving_origin, "Map and moving platform stay frozen")
	room._challenge(Chapter1WindRoom.PUZZLE_ID, MinigameStele.SteleKind.PUZZLE)
	check(room._puzzle_game == game, "Duplicate window is prevented")
	await key(KEY_E)
	check(room._puzzle_game == game, "E in window does not reopen map challenge")
	await capture("wind_puzzle_window.png")
	await key(KEY_ESCAPE)
	check(not paused and not is_instance_valid(room._puzzle_game), "Esc closes window and resumes map")
	check(room.player.position == origin, "Return preserves player position")
	check(room.puzzle.state == MinigameStele.SteleState.UNLOCKED, "Leaving ready window grants no completion")
	await capture("wind_puzzle_map.png")
	await key(KEY_E)
	# Inject result to isolate the save contract from the flight simulation.
	save.writes_fail = true
	room._puzzle_game.result_ready.emit(true, 1234)
	check(room.puzzle.state == MinigameStele.SteleState.UNLOCKED and save.get_stele_best_score(Chapter1WindRoom.PUZZLE_ID) == 0, "Failed result save rolls back score and completion")
	check(room._puzzle_game._save_button.visible, "Save failure offers retry")
	save.writes_fail = false
	room._puzzle_game.retry_save_requested.emit()
	check(room.puzzle.state == MinigameStele.SteleState.COMPLETED and save.get_stele_best_score(Chapter1WindRoom.PUZZLE_ID) == 1234, "Retry commits future game result")
	check(room.combat.state != MinigameStele.SteleState.COMPLETED, "Puzzle completion does not require combat completion")
	room._puzzle_game.close()
	await frames()
	await key(KEY_E)
	check(room._puzzle_game.previously_completed and room._puzzle_game.best_score == 1234, "Replay receives existing completion and record")
	room._puzzle_game.result_ready.emit(false, 10)
	check(room.puzzle.state == MinigameStele.SteleState.COMPLETED and save.get_stele_best_score(Chapter1WindRoom.PUZZLE_ID) == 1234, "Failed replay preserves completion and best score")
	room._puzzle_game.close()
	await frames()
	room.player.reset_after_map_fall(room.combat.position)
	await frames()
	await key(KEY_E)
	await key(KEY_E)
	room._update_combat(1.0)
	check(room.combat_active and room._enemies.size() == 2, "Combat still starts first wave")
	for enemy in room._enemies.duplicate():
		enemy.state = MistAmbusher.State.WARNING
		enemy.receive_hit(99, room.player.position)
	room._update_combat(2.0)
	check(room.combat_active and room._enemies.size() == 3, "Combat starts second wave")
	for enemy in room._enemies.duplicate():
		enemy.state = MistAmbusher.State.WARNING
		enemy.receive_hit(99, room.player.position)
	room._update_combat(2.0)
	check(room.combat.state == MinigameStele.SteleState.COMPLETED, "Both challenges record completion")
	room._open_puzzle()
	await frames()
	room.remove_child(room._puzzle_game)
	check(not paused, "Unexpected window removal restores pause state")
	room._puzzle_game.free()
	room._puzzle_game = null
	save.save_stele_checkpoint(Chapter1WindRoom.PUZZLE_ID, room.scene_file_path, Vector2(514,1380))
	root.remove_child(room)
	room.free()
	room = load("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames(5)
	check(room.puzzle.state == MinigameStele.SteleState.COMPLETED, "Reload restores existing progress")
	check(absf(room.player.position.y-room.puzzle.position.y)<5, "Old saved puzzle position resolves to relocated stele")
	print("WIND CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

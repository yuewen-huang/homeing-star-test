extends SceneTree
var failures := 0
var checks := 0
var room: Node
var game: RuneLockGame
var output_directory := "user://rune_lock_acceptance/"
var original_save := PackedByteArray()
class FailingSave extends SaveProgressService:
	func save_progress() -> bool: return false

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	root.push_input(event)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join(name+".png"))

func hit(kind: int) -> void:
	for bar in game.model.bars:
		if int(bar.kind) == kind:
			game.model.angle = float(bar.angle)
			key(KEY_SPACE)
			return

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output_directory = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output_directory)
	original_save = FileAccess.get_file_as_bytes("res://save/progress.cfg")
	var backup := FileAccess.open(output_directory.path_join("progress.cfg.backup"), FileAccess.WRITE)
	backup.store_buffer(original_save)
	backup.close()
	var save := root.get_node("SaveProgress") as SaveProgressService
	save._config.set_value("steles", "mist_puzzle_entry", 0)
	save._config.set_value("stele_scores", "mist_puzzle_entry", 0)
	room = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.player.position = Vector2(340,555)
	await process_frame
	var stele := room.get_node("PuzzleStele") as MinigameStele
	check(stele.state == 0, "Initially gray")
	key(KEY_E)
	await process_frame
	check(stele.state == 1 and save.get_checkpoint_for_scene(room.scene_file_path).position == Vector2(336,555), "E unlocks and saves checkpoint")
	key(KEY_E)
	await process_frame
	game = room._rune_lock_game
	check(is_instance_valid(game) and paused, "Second E opens modal and pauses world")
	await capture("rune_intro")

	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050*10)
	samples.fill(128)
	wave.data = samples
	transition.music_player.stream = wave
	transition.music_player.play(1.0)
	var playback_before := transition.music_player.get_playback_position()
	await create_timer(0.3).timeout
	check(transition.music_player.stream == wave and transition.music_player.get_playback_position() > playback_before, "BGM advances while world is paused")

	key(KEY_SPACE)
	check(game.model.phase == RuneLockModel.Phase.RUNNING, "Space starts")
	var before_position: Vector2 = room.player.position
	hit(0)
	hit(1)
	check(game.model.score == 1000 and game.model.hits == 2, "Space strikes score and time")
	for i in range(4): hit(0)
	await capture("rune_running")
	key(KEY_ESCAPE)
	var time_before := game.model.time_left
	await create_timer(0.2).timeout
	check(game._locally_paused and is_equal_approx(time_before,game.model.time_left), "Esc pauses minigame time")
	check(room.player.position.is_equal_approx(before_position), "World player remains frozen")
	await capture("rune_pause")
	key(KEY_ESCAPE)
	check(not game._locally_paused, "Esc resumes")
	var mouse := InputEventMouseButton.new()
	mouse.position = game._dial.get_global_transform() * (game._dial.size*0.5)
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	for bar in game.model.bars:
		if int(bar.kind)==0:
			game.model.angle = bar.angle
			break
	root.push_input(mouse)
	check(game.model.score == 6000, "Left click hits wheel")
	game.model.advance(60)
	await process_frame
	check(stele.state == 2 and save.get_stele_best_score(&"mist_puzzle_entry")==6000, "Win saves completion and best score")
	await capture("rune_success")
	game.set_save_result(false,6000)
	check(game._save_button.visible, "Failed save exposes retry")
	game._retry_save()
	check(not game._save_button.visible, "Save retry succeeds")
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and room._rune_lock_game == null, "Result Esc returns to world")
	await capture("rune_world_completed")
	key(KEY_E)
	await process_frame
	game = room._rune_lock_game
	check(is_instance_valid(game) and game.previously_completed and game.best_score == 6000, "Completed stele supports replay")
	game.start_round(44)
	game.model.advance(16)
	await process_frame
	check(stele.state == 2 and save.get_stele_best_score(&"mist_puzzle_entry") == 6000, "Failed replay keeps completion and best score")
	await capture("rune_failure")

	root.content_scale_size = Vector2i(960,540)
	root.size = Vector2i(960,540)
	await process_frame
	await process_frame
	game._fit_layout()
	game.start_round(17)
	game._locally_paused = true
	game._pause_overlay.visible = false
	var scaled_mouse := InputEventMouseButton.new()
	scaled_mouse.position = game._dial.get_global_transform() * (game._dial.size*0.5)
	scaled_mouse.button_index = MOUSE_BUTTON_LEFT
	scaled_mouse.pressed = true
	game._locally_paused = false
	for bar in game.model.bars:
		if int(bar.kind)==0:
			game.model.angle = bar.angle
			break
	root.push_input(scaled_mouse)
	check(game.model.score == 1000, "Scaled wheel click maps correctly")
	await capture("rune_scaled")
	game._close()
	await process_frame
	save.load_progress()
	check(save.get_stele_state(&"mist_puzzle_entry")==2 and save.get_stele_best_score(&"mist_puzzle_entry")==6000, "Reload restores completed state and record")
	root.content_scale_size = Vector2i(1280,720)
	root.size = Vector2i(1280,720)

	key(KEY_E)
	await process_frame
	game = room._rune_lock_game
	game.start_round(42)
	key(KEY_F10)
	check(save.get_stele_state(&"mist_puzzle_entry")==2, "GM reset key blocked in modal")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game._locally_paused, "Focus loss pauses")
	game._close()
	await process_frame
	check(not paused, "Abandon restores world")
	var fail_save := FailingSave.new()
	fail_save._loaded = true
	fail_save._config.set_value("steles","test",1)
	fail_save._config.set_value("stele_scores","test",1000)
	check(not fail_save.record_stele_minigame_result(&"test",6000,true), "Disk failure reported")
	check(fail_save.get_stele_state(&"test")==1 and fail_save.get_stele_best_score(&"test")==1000, "Disk failure rolls back both state and score")
	fail_save.free()
	transition.music_player.stop()
	transition.music_player.stream = null
	wave = null
	await process_frame
	print("RUNE INTEGRATION: %d checks, %d failures" % [checks,failures])
	var restore := FileAccess.open("res://save/progress.cfg", FileAccess.WRITE)
	restore.store_buffer(original_save)
	restore.close()
	quit(1 if failures else 0)

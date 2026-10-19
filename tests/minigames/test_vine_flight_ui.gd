extends SceneTree
class MemoryProgress extends SaveProgressService:
	var writes_fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return not writes_fail
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true
var capture_dir := ""
var checks := 0
var failures := 0
var game: VineFlightGame
var room: Chapter1VineRoom
var save: MemoryProgress
var save_bytes: PackedByteArray
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	save_bytes = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	print("OK " if ok else "FAIL ",label)
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n: await process_frame
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event)
func mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	root.push_input(event)
func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion)
	await frames(2)
	mouse(at,true)
	await frames(2)
	mouse(at,false)
	await frames(2)
func capture(label: String) -> void:
	if capture_dir.is_empty(): return
	await frames(3)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_dir.path_join(label+".png")) == OK,label+" render")
func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemoryProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save.set_stele_state(&"vine_puzzle_high_swing",1)
	room = load("res://scenes/levels/chapter_1/chapter_1_vine_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	room.camera.position_smoothing_enabled = false
	await frames(3)
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var music := transition.music_player.stream
	var music_time := transition.music_player.get_playback_position()
	var frozen := room.player.position
	room._open_flight()
	game = room._flight_game
	game.set_process(false)
	check(paused and game.field.size == Vector2(1130,500),"modal pauses world and uses a wide playfield")
	check(game._progress.size.y <= 6, "progress strip remains thin after theme layout")
	check(not game._readout.visible and not game._score_label.visible,"ready screen hides active statistics")
	await capture("vine_ready_final")
	await click(game._start.get_global_rect().get_center())
	check(game.model.phase == VineFlightModel.Phase.RUNNING and not game._mouse_held,"actual start-button click works without latching the shooting input")
	key(KEY_SPACE,true)
	game.model.advance(0.05,game._key_held)
	game._sync_ui()
	check(game.model.shot_target >= 0 and game.model.attached < 0,"real Space launches a visible traveling vine")
	await capture("vine_shoot_final")
	game.model.advance(0.08,game._key_held)
	check(game.model.attached >= 0,"held Space completes attachment")
	await capture("vine_swing_final")
	var release_x := game.model.velocity.x
	key(KEY_SPACE,false)
	game.model.advance(game.model.STEP,game._key_held)
	check(game.model.attached < 0 and absf(game.model.velocity.x-release_x)<1,"real release keeps forward speed")
	await capture("vine_release_final")
	key(KEY_SPACE,true)
	for tick in 36:
		game.model.advance(game.model.STEP,game._key_held)
		if game.model.shot_target >= 0: break
	check(game.model.shot_target > game.model.blocked_vine,"real second press shoots toward the following anchor")
	await capture("vine_reconnect_final")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	var elapsed := game.model.elapsed
	game.set_process(true)
	await frames(10)
	check(game._locally_paused and is_equal_approx(elapsed,game.model.elapsed),"Escape freezes local simulation and timer")
	game.set_process(false)
	await capture("vine_pause_final")
	game._toggle_help()
	check(game._help_overlay.visible,"help opens over pause")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	check(not game._help_overlay.visible and game._locally_paused,"closing help restores previous pause state")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	check(not game._locally_paused,"Escape resumes the challenge")
	game._toggle_help()
	await capture("vine_help_final")
	game._toggle_help()
	check(not game._locally_paused,"help opened during play resumes normally")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.set_process(true)
	elapsed = game.model.elapsed
	await frames(10)
	check(game._locally_paused and is_equal_approx(game.model.elapsed,elapsed),"focus loss freezes the challenge")
	game.set_process(false)
	game._toggle_pause()
	var catches := [0]
	game.model.feedback.connect(func(kind,_at):
		if kind == "catch": catches[0] += 1)
	for i in 2800:
		if game.model.phase == VineFlightModel.Phase.FINISHED: break
		var m := game.model
		var held := m.shot_target >= 0 or m.candidate() >= 0
		if m.attached >= 0: held = not (m.omega > 0 and m.angle >= 0.4)
		if held != game._key_held: key(KEY_SPACE,held)
		m.advance(1.0/60,game._key_held)
		game._sync_ui()
		if i == 180: await capture("vine_relay_final")
		await process_frame
	check(catches[0]>15,"real alternating key events sustain many consecutive grapples")
	check(game.model.phase == VineFlightModel.Phase.FINISHED and game.model.score>=4000,"actual-input round finishes above the target")
	check(room.puzzle.state == MinigameStele.SteleState.COMPLETED and game._save_ok,"map completion and record use the existing save interface")
	check(room.player.position == frozen,"world stays frozen throughout the minigame")
	check(transition.music_player.stream == music and transition.music_player.playing and transition.music_player.get_playback_position()>music_time,"existing BGM continues during the modal")
	await capture("vine_result_final")
	game._close()
	key(KEY_SPACE,false)
	await frames(3)
	check(not paused and not is_instance_valid(room._flight_game),"close restores the world and releases the minigame")
	room._open_flight()
	game = room._flight_game
	game.set_process(false)
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(960,540)
	await frames(3)
	check(is_equal_approx(game._layout.scale.x,0.75),"960 by 540 scales the complete window uniformly")
	mouse(game.field.get_global_transform()*Vector2(300,220),true)
	check(game.model.phase == VineFlightModel.Phase.RUNNING and game._mouse_held,"scaled left click starts and holds shooting")
	game.model.advance(0.04,game._mouse_held)
	mouse(Vector2.ZERO,false)
	game.model.advance(0.02,game._mouse_held)
	check(not game._mouse_held and game.model.shot_target < 0,"release outside the field cancels the current shot")
	await capture("vine_small_final")
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	await frames(3)
	var old_best := save.get_stele_best_score(room.PUZZLE_ID)
	game.model.score = old_best + 2000
	save.writes_fail = true
	game.model.finish()
	check(not game._save_ok and game._retry.visible and save.get_stele_best_score(room.PUZZLE_ID) == old_best,"failed save preserves the previous record and exposes retry")
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	check(game.model.phase == VineFlightModel.Phase.FINISHED,"failed save cannot be lost by a keyboard restart")
	await capture("vine_save_failed_final")
	save.writes_fail = false
	await click(game._retry.get_global_rect().get_center())
	check(game._save_ok and not game._retry.visible,"actual retry-button click saves the pending result")
	await click(game._start.get_global_rect().get_center())
	check(game.model.phase == VineFlightModel.Phase.RUNNING,"actual replay-button click starts a fresh round")
	var snapshot := save._config.encode_to_text()
	game._close()
	await frames(3)
	check(snapshot == save._config.encode_to_text(),"abandoning a round does not write a result")
	check(save_bytes == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH),"real player save bytes remain untouched")
	room.queue_free()
	await frames(3)
	print("VINE FLIGHT UI: ",checks," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)

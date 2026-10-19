extends SceneTree

class TestProgress extends SaveProgressService:
	var writes_fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return not writes_fail
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var failures := 0
var game: WindPuzzleGame
var save: TestProgress

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok:
		failures += 1

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
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
	var room := load("res://scenes/levels/chapter_1/chapter_1_wind_room.tscn").instantiate() as Chapter1WindRoom
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	save.set_stele_state(Chapter1WindRoom.PUZZLE_ID,1)
	room._open_puzzle()
	game = room._puzzle_game
	await frames()
	await capture("wind_flight_ready.png")
	await key(KEY_SPACE,true)
	await key(KEY_SPACE,false)
	check(game.model.phase==WindFlightModel.Phase.FLIGHT,"Space starts real flight")
	check(not game._stamina.visible and not game._stamina_label.visible,"Flight hides irrelevant stamina readout")
	await key(KEY_W,true)
	game.model.advance(0.4,game._up,game._down,false)
	check(game.model.vertical_speed<0,"W input drives ascent animation")
	await frames(5)
	await capture("wind_flight_rise.png")
	await key(KEY_W,false)
	game.model.advance(0.4)
	game.model.walls = [{"x":450.0,"width":52.0,"gap":235.0,"height":190.0}]
	await frames(5)
	await capture("wind_flight_glide.png")
	# Put each of the two mirrored edge joins in the middle of the viewport.
	game.model.travel_distance = 840*0.5/1.3
	await capture("wind_flight_mirror_right_edge.png")
	game.model.travel_distance = 840*1.5/1.3
	await capture("wind_flight_mirror_left_edge.png")
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	var clock := game.model.elapsed
	await frames(15)
	check(game._locally_paused and game.model.elapsed==clock,"Esc freezes local game")
	await capture("wind_flight_pause.png")
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	check(not game._locally_paused and paused,"Resume keeps underlying map paused")
	game.model._enter_turbulence()
	game._sync_ui()
	check(game._stamina.visible and game._stamina_label.visible,"Turbulence shows stamina readout")
	await key(KEY_W,true)
	game.model.advance(0.15,game._up,game._down,game._up)
	check(game.model.bar_speed<0,"W controls fishing bar during turbulence")
	await key(KEY_W,false)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(760,300)
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await frames(2)
	check(game._mouse_held,"Mouse press on playfield holds fishing bar")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await frames(2)
	check(not game._mouse_held,"Mouse release lets fishing bar fall")
	game.model.bar_center = 0.48
	game.model.wind_target = 0.49
	game.model.stamina = 0.64
	await capture("wind_flight_turbulence.png")
	game.model.bar_center = 0.5
	game.model.bar_speed = 0
	game.model.wind_target = 0.5
	game.model.wind_speed = 0
	game.model._wind_goal = 0.5
	game.model.stamina = 0.9999
	game.model.advance(WindFlightModel.STEP)
	await frames(2)
	check(game.model.boost_left>1.8 and game._boost_voice.playing,"Clearing turbulence starts boost and reward sound")
	check(not game._stamina.visible,"Boost hides stamina")
	await capture("wind_flight_boost.png")
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	var bonus_clock := game.model.boost_left
	await frames(10)
	check(game.model.boost_left==bonus_clock,"Local pause freezes bonus duration")
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	game.model._enter_turbulence()
	game.model.bar_center = 0.85
	game.model.wind_target = 0.2
	game.model._wind_goal = 0.2
	game.model.stamina = 0.0001
	save.writes_fail = true
	game.model.advance(WindFlightModel.STEP)
	check(game.model.phase==WindFlightModel.Phase.FINISHED and game._save_button.visible,"Real fall result offers failed-save retry")
	game.close()
	check(is_instance_valid(room._puzzle_game),"Pending failed result remains available for retry")
	await frames(10)
	await capture("wind_flight_failure.png")
	save.writes_fail = false
	game.retry_save_requested.emit()
	check(game._save_ok,"Retry persists actual fall result")
	await key(KEY_SPACE,true)
	await key(KEY_SPACE,false)
	check(game.model.phase==WindFlightModel.Phase.FLIGHT and game.model.score<5,"Replay resets round")
	check(game.model.boost_left==0 and game._achievement_time==0,"Replay clears boost and milestone effects")
	game.model.distance = 999.999
	game.model.advance(WindFlightModel.STEP)
	check(room.puzzle.state==MinigameStele.SteleState.COMPLETED and game.model.is_running(),"Distance milestone saves completion without ending flight")
	game._sync_ui()
	check(game._achievement_flash.modulate.a>0 and game._achievement_label.visible and game._achievement_voice.playing,"Milestone produces full-window flash, announcement and sound")
	await capture("wind_flight_milestone.png")
	game.close()
	await frames()
	check(not paused and not is_instance_valid(room._puzzle_game),"Ending flight saves score and returns to map")
	print("WIND FLIGHT WINDOW CHECKS: ",failures," failures")
	quit(1 if failures else 0)

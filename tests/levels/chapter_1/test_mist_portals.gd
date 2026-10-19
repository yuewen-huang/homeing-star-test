extends SceneTree

class UnlockedProgress extends SaveProgressService:
	func _ready() -> void:
		pass
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var failures := 0
func _initialize() -> void:
	call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func prepare_room(room: Node) -> LanPlayer:
	var target := room.get("player") as LanPlayer
	var progress := UnlockedProgress.new()
	target.add_child(progress)
	target.save_progress = progress
	target.save_progress_resolved = true
	if room.get("mist_enemies") != null:
		for enemy: MistAmbusher in room.mist_enemies:
			enemy.set_physics_process(false)
			enemy.attack_hitbox.deactivate()
	return target
func capture(name: String) -> void:
	if OS.get_cmdline_user_args().size() != 2:
		return
	var camera := current_scene.get("camera") as Camera2D
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_cmdline_user_args()[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func use_portal(room: Node) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_E
	room._unhandled_input(event)
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in range(300):
		await physics_frame
		if not transition.is_transitioning:
			return
	check(false, "Portal transition did not finish")

func run_tests() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	transition.take_scene_entry_position()
	var room = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player := prepare_room(room)
	player.position = Vector2(820,555)
	room.camera.position_smoothing_enabled = false
	await capture("left_stairs")
	player.position = Vector2(621,555)
	var route := [1,3,4]
	for index in range(route.size()):
		var piece := room.get_node("WindSteps/WindStep%d" % route[index]) as TerrainPiece
		var direction := signf(piece.position.x + piece._walk_length() / 2 - player.position.x)
		if index > 0:
			var previous := room.get_node("WindSteps/WindStep%d" % route[index-1]) as TerrainPiece
			var launch_x: float = previous.position.x + (18.0 if direction < 0 else previous._walk_length()-18.0)
			var move_action := &"ui_left" if direction < 0 else &"ui_right"
			Input.action_press(move_action)
			for i in range(90):
				await physics_frame
				if (player.position.x - launch_x) * direction >= -6:
					break
			Input.action_release(move_action)
			for i in range(8):
				await physics_frame
		var target_x: float = piece.position.x + (piece._walk_length()-35 if direction < 0 else 35)
		if index == 0:
			target_x = player.position.x
			direction = 0
		var action := &"ui_left" if direction < 0 else &"ui_right"
		if direction != 0:
			Input.action_press(action)
		Input.action_press(&"jump")
		for i in range(3):
			await physics_frame
		Input.action_release(&"jump")
		var landed := false
		for i in range(150):
			await physics_frame
			# Current editor-authored steps exceed a single jump's ~103px rise.
			if i == 20:
				Input.action_press(&"jump")
			elif i == 22:
				Input.action_release(&"jump")
			if direction != 0 and (player.position.x - target_x) * direction >= 0:
				Input.action_release(action)
			if i > 25 and player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING]:
				landed = true
				break
		Input.action_release(action)
		Input.action_release(&"jump")
		await process_frame
		check(landed and is_equal_approx(player.position.y,piece.position.y), "Current double-jump route failed step %d at %s" % [index+1,player.position])
		if failures:
			quit(1)
			return

	check(room._portals[1].prompt.can_interact(), "Top step does not reach Wind portal")
	await capture("wind_top")
	await use_portal(room)
	check(current_scene.scene_file_path.ends_with("chapter_1_wind_room.tscn"), "Wind portal wrong target")
	room = current_scene
	player = prepare_room(room)
	check(player.position.distance_to(room.get_node("Portals/MistGate").position) < 12.0, "Wind entry unsafe")
	player.set_physics_process(false)
	await use_portal(room)
	room = current_scene
	check(room.scene_file_path.ends_with("chapter_1_mist_room.tscn"), "Wind return wrong target")
	player = prepare_room(room)
	for i in range(8):
		await physics_frame
	check(player.position.distance_to(room.get_node("WindSteps/WindStep4/PortalToWind").global_position)<2, "Wind return did not stay on top step")
	player.position = room.get_node("PortalToSpecialBoss").position
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	await capture("right_portals")
	await use_portal(room)
	room = current_scene
	check(room.scene_file_path.ends_with("chapter_1_special_boss_lower_left_room.tscn"), "Special Boss portal wrong target")
	player = prepare_room(room)
	check(player.position.distance_to(room.get_node("Entry").position) < 12.0, "Special Boss arrival unsafe")
	player.set_physics_process(false)
	player.position = room.get_node("ReturnGate").position
	await process_frame
	await use_portal(room)
	room = current_scene
	check(room.scene_file_path.ends_with("chapter_1_mist_room.tscn"), "Special Boss return wrong target")
	player = prepare_room(room)
	check(player.position.distance_to(room.get_node("PortalToSpecialBoss").position) < 12.0, "Special Boss return unsafe")
	room.queue_free()
	await process_frame
	# Emulate editor movement and saving/reopening the scene, without touching the user's scene file.
	var edited = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	edited.get_node("WindSteps").position = Vector2(10,0)
	edited.get_node("WindSteps/WindStep2").position += Vector2(32,-14)
	edited.get_node("WindSteps/WindStep4").position = Vector2(220,300)
	edited.get_node("WindSteps/WindStep4/PortalToWind").position = Vector2(65,0)
	var saved_scene := PackedScene.new()
	check(saved_scene.pack(edited) == OK, "Edited platforms could not be saved")
	edited.free()
	edited = saved_scene.instantiate()
	transition.set_scene_entry_anchor(NodePath("WindSteps/WindStep4/PortalToWind"))
	root.add_child(edited)
	current_scene = edited
	player = prepare_room(edited)
	for i in range(8):
		await physics_frame
	check(player.position.is_equal_approx(Vector2(295,300)), "Edited wind return was overwritten by a hardcoded position")
	check(player.ground_surfaces.has(Rect2(edited.get_node("WindSteps/WindStep2").global_position, Vector2(edited.get_node("WindSteps/WindStep2")._walk_length(),1))), "Edited step collision did not follow its scene node")
	check(player.ground_surfaces.has(Rect2(230,300,176.8,1)), "Edited top-step collision incorrect")
	check(edited._portals[1].prompt.can_interact() and edited._portals[1].anchor == edited.get_node("WindSteps/WindStep4/PortalToWind"), "Wind prompt did not follow the edited marker")
	check(transition.take_scene_entry_anchor().is_empty(), "Entry anchor leaked into the next transition")
	await capture("edited_steps")
	edited.queue_free()
	await process_frame
	transition.music_player.stop()
	for i in range(4):
		await process_frame
	if failures == 0:
		print("PASS: current editor-authored Wind route with double jumps; Wind portal and elevated round trip; Special Boss lower-left round trip; Root exit retained; editor-moved and saved platforms/marker retain art, collision and return spawn")
	quit(1 if failures else 0)

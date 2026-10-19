extends "vine_region_test_driver.gd"
var save_bytes: PackedByteArray

func crossing(start_x: float, target_name: String, direction: float, limit := 2400) -> bool:
	release_inputs()
	await walk_to(start_x)
	var target: TerrainPiece = room.get_node("Terrain/" + target_name)
	if target_name == "ArenaRest" and direction > 0:
		var moving: VineTrialPiece = room.get_node("Terrain/MainSway")
		for i in 360:
			if moving.vine_angle() < -0.4 and moving._vine_omega > 0: break
			await physics_frame
	if target_name == "HighPerch" and direction > 0:
		var moving: VineTrialPiece = room.get_node("Terrain/UpperSway")
		for i in 720:
			var projected := player.position + Vector2(60, -170) - moving.vine_pivot()
			var future := moving.vine_angle() + moving._vine_omega * 0.4
			var along := projected.dot(Vector2(sin(future), cos(future)))
			var off := absf(projected.dot(Vector2(cos(future), -sin(future))))
			if off < 22 and along > moving.min_grab_radius and along < moving.vine_length: break
			await physics_frame
	if target_name == "ArenaRest" and direction < 0:
		var returning: VineTrialPiece = room.get_node("Terrain/MainReturn2")
		for i in 360:
			if absf(returning.vine_angle()) < 0.06: break
			await physics_frame
		print("RETURN ROPE angle=",returning.vine_angle()," omega=",returning._vine_omega," block=",player._vine_regrab_block)
	drive(direction)
	print("TAKEOFF ", target_name," ", player.position," air=",player.air_state," velocity=",player.velocity," jump-held=",player.jump_was_pressed," accept=",Input.is_action_pressed("ui_accept"))
	Input.action_press(&"jump")
	await frames(3)
	print("JUMP STATE ",target_name," ",player.position," air=",player.air_state," defense=",player.defense_state," vel=",player.velocity)
	Input.action_release(&"jump")
	var grabbed := false
	var last: TerrainPiece
	for i in limit:
		if player.vine != last:
			print("GRIP ", target_name," ",player.vine.name if player.vine else "none"," ",player.position)
			last = player.vine
		if player.vine:
			grabbed = true
			var over_target := player.position.x > target.position.x + 40 and player.position.x < target.position.x + target.length - 40 and player.position.y < target.position.y - 20
			if over_target or (player.vine_angle * direction > 0.6 and player.vine_omega * direction > 0 and absf(player.vine_omega * player.vine_radius) > 320):
				Input.action_press(&"parry")
				drive(direction)
			else:
				Input.action_release(&"parry")
				drive(signf(player.vine_omega) if absf(player.vine_omega) > 0.08 else direction)
		else:
			if grabbed and player.position.x > target.position.x + 50 and player.position.x < target.position.x + target.length - 50:
				Input.action_press(&"parry")
				drive(0)
			else:
				Input.action_release(&"parry")
				drive(direction)
		await physics_frame
		if room._standing_on(target) and ground():
			release_inputs()
			await frames(15)
			return grabbed
		if player.position.y > target.position.y + 200:
			break
	print("CROSS END ",target_name," ",player.position)
	release_inputs()
	return false

func ascend(vine_name: String, target_name: String) -> bool:
	var vine: VineTrialPiece = room.get_node("Terrain/" + vine_name)
	var target: TerrainPiece = room.get_node("Terrain/" + target_name)
	release_inputs()
	await walk_to(vine.position.x)
	await frames(20)
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	var grabbed := false
	for i in 1800:
		if player.vine == vine:
			grabbed = true
			if player.position.y < target.position.y - 30:
				Input.action_press(&"parry")
		if grabbed and player.vine == null:
			Input.action_press(&"parry")
			drive(signf(target.position.x + target.length * 0.5 - player.position.x) if player.position.x < target.position.x + 30 or player.position.x > target.position.x + target.length - 30 else 0)
		await physics_frame
		if grabbed and room._standing_on(target) and ground():
			release_inputs()
			await frames(15)
			print("ASCENDED ",vine_name," ",player.position," air=",player.air_state," target=",target._walk_rect())
			return true
	print("ASCEND END ",vine_name," ",player.position, " grip=",player.vine)
	release_inputs()
	return false

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	save_bytes = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	room = load("res://scenes/levels/chapter_1/chapter_1_vine_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	player = room.player
	await frames(20)
	check(room._standing_on(room.get_node("Terrain/WindRest")), "wind arrival is a stable upper branch")
	check(await crossing(620, "UpperWest", 1), "upper short vines cross to first branch")
	# Deliberate failed upper attempt: release and descend to the middle route.
	release_inputs()
	Input.action_press(&"parry")
	drive(-1)
	for i in 600:
		await physics_frame
		if player.position.x < 1020: drive(0)
		if ground() and room._standing_on(room.get_node("Terrain/MainWest")): break
	release_inputs()
	check(room._standing_on(room.get_node("Terrain/MainWest")), "upper failure lands on traversable middle branch")
	check(await crossing(1370, "ArenaRest", 1), "middle route uses driven vine and return relay")
	check(await crossing(2900, "MainEast", 1), "middle route crosses break vine to east branch")
	# Walk off the east branch toward root-net exit without unlocking a stele.
	await walk_to(4640)
	Input.action_press(&"parry")
	drive(1)
	for i in 600:
		await physics_frame
		if player.position.x > 4710: drive(0)
		if ground() and room._standing_on(room.get_node("Terrain/RootRest")): break
	release_inputs()
	check(room._standing_on(room.get_node("Terrain/RootRest")), "main route descends safely to root gate without either stele")
	check(await ascend("EastRecovery", "MainEast"), "root side recovery reel reaches middle")
	check(await crossing(3550, "ArenaRest", -1), "reverse middle route crosses east canyon")
	check(await crossing(1940, "MainWest", -1), "reverse middle route crosses west canyon")
	check(await ascend("WindReel", "WindRest"), "reverse route returns to wind without a stele unlock")
	# Other recovery shafts + optional high branch tested from their real rest.
	for data in [["LowerWest", "WestRecovery", "MainWest"], ["LowerMiddle", "MiddleRecovery", "ArenaRest"], ["ArenaRest", "HighReel", "HighPerch"]]:
		var platform: TerrainPiece = room.get_node("Terrain/" + data[0])
		player.reset_after_map_fall(platform.position + Vector2(150,0))
		await frames(15)
		check(await ascend(data[1], data[2]), data[1] + " connects its two layers")
	# E unlock, second E launches the shared-format independent minigame.
	await walk_to(room.puzzle.position.x - 45)
	print("PUZZLE approach ",player.position," grounded=",ground()," can=",room.puzzle.can_interact()," state=",room.puzzle.state)
	await e()
	check(room.puzzle.state == MinigameStele.SteleState.UNLOCKED and not is_instance_valid(room._flight_game), "first E unlocks and saves without completing")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	transition.play_music(load("res://assets/levels/town/audio/homeward_town_day.mp3"))
	var music := transition.music_player.stream
	var music_position := transition.music_player.get_playback_position()
	await e()
	check(is_instance_valid(room._flight_game) and paused, "second E opens flight minigame and freezes map")
	if not is_instance_valid(room._flight_game):
		quit(1)
		return
	var game: VineFlightGame = room._flight_game
	var frozen := player.position
	key(KEY_SPACE, true)
	await frames(5)
	check(game.model.phase == VineFlightModel.Phase.RUNNING and game._key_held, "real Space starts and holds vine")
	key(KEY_SPACE, false)
	await frames(5)
	check(not game._key_held, "real Space release detaches")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames(5)
	var elapsed := game.model.elapsed
	await frames(15)
	check(game._locally_paused and is_equal_approx(game.model.elapsed, elapsed), "Escape freezes local timer")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames(3)
	check(not game._locally_paused and player.position == frozen, "resume keeps map frozen")
	# Play actual window with key events until its 45-second result.
	for i in 4000:
		if game.model.phase == VineFlightModel.Phase.FINISHED: break
		var held := game.model.shot_target >= 0 or game.model.candidate() >= 0
		if game.model.attached >= 0: held = game.model.held_time < 0.8
		if held != game._key_held: key(KEY_SPACE, held)
		await physics_frame
	check(game.model.phase == VineFlightModel.Phase.FINISHED and room.puzzle.state == MinigameStele.SteleState.COMPLETED, "45-second real-input game commits completion")
	check(save.get_stele_best_score(room.PUZZLE_ID) > 0 and game._save_ok, "result stores best score with completion")
	check(transition.music_player.playing and transition.music_player.stream == music and transition.music_player.get_playback_position() > music_position, "BGM continues advancing throughout frozen-map minigame")
	game._close()
	key(KEY_SPACE, false)
	await frames(5)
	check(not paused and not is_instance_valid(room._flight_game), "closing restores map and releases overlay")
	player.reset_after_map_fall(room.combat.position + Vector2(-45, 0))
	await frames(10)
	await e()
	await e()
	check(room.combat_active and room._enemies.size() == 3, "combat stele activates three existing map vines")
	var ordinary := room._enemies[2]
	for enemy in room._enemies: enemy.next_attack = INF
	player.reset_after_map_fall(ordinary.home + Vector2(-48, 65))
	player.facing_direction = 1
	var before_health: int = ordinary.combat_stats.health
	key(KEY_J, true)
	await frames(3)
	key(KEY_J, false)
	await frames(55)
	check(ordinary.combat_stats.health < before_health, "real J attack hitbox damages a living vine")
	for enemy in room._enemies.duplicate(): enemy.receive_hit(99, player.position)
	await frames(5)
	check(not room.combat_active and room.combat.state == MinigameStele.SteleState.COMPLETED, "defeating all three vines completes combat stele")
	room._challenge(room.COMBAT_ID, 0)
	await frames(5)
	check(not room.combat_active and room._enemies.is_empty(), "completed combat stele cannot reactivate the vines")
	room._on_death()
	await frames(5)
	check(not room.combat_active and player.combat_stats.health > 0, "death revives without revoking completion")
	room._open_flight()
	game = room._flight_game
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	await frames(5)
	check(is_equal_approx(game._layout.scale.x, 0.75), "960 by 540 scales complete overlay uniformly")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = game.field.get_global_transform() * Vector2(300, 220)
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await frames(5)
	check(game._mouse_held and game.model.phase == VineFlightModel.Phase.RUNNING, "scaled real left click starts and holds")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await frames(5)
	check(not game._mouse_held, "left release outside field still releases")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var focus_elapsed := game.model.elapsed
	await frames(10)
	check(game._locally_paused and is_equal_approx(game.model.elapsed, focus_elapsed), "focus loss pauses countdown")
	game._toggle_pause()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	await frames(3)
	game.model.score = 12345
	save.writes_fail = true
	game.model.finish()
	check(not game._save_ok and game._retry.visible and save.get_stele_best_score(room.PUZZLE_ID) != 12345, "failed save preserves old record and exposes retry")
	save.writes_fail = false
	game._retry_save()
	check(game._save_ok and room.puzzle.state == MinigameStele.SteleState.COMPLETED, "retry commits without losing previous completion")
	game._close()
	key(KEY_SPACE, false)
	await frames(5)
	room._open_flight()
	game = room._flight_game
	var progress_snapshot := save._config.encode_to_text()
	game.start_round(9)
	await frames(10)
	game._close()
	await frames(5)
	check(save._config.encode_to_text() == progress_snapshot, "abandoning an unfinished round writes no result")
	check(save_bytes == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "player save bytes unchanged")
	# Old entry coordinates and invalid legacy checkpoints must never spawn in air.
	for pair in [[Chapter1Layout.VINE_ENTRANCE, "WindGate"], [Chapter1Layout.VINE_ROOT_EXIT, "RootGate"], [Chapter1Layout.VINE_SPECIAL_BOSS_EXIT, "DeerGate"], [Chapter1Layout.VINE_FINAL_BOSS_EXIT, "HeartGate"]]:
		transition.set_scene_entry_position(pair[0])
		check(room._resolve_spawn() == room.get_node("Portals/" + pair[1]).position, "legacy portal maps to " + pair[1])
	save.save_stele_checkpoint(&"vine_legacy_test", room.scene_file_path, Vector2(6500, 1100))
	check(room._resolve_spawn() == room.get_node("Portals/WindGate").position, "invalid old checkpoint falls back to safe wind rest")
	for marker_name in ["HeartGate", "DeerGate"]:
		await travel(room.get_node("Portals/" + marker_name))
		check(current_scene is Chapter1BossRoom, "boss portal at " + marker_name + " opens prepared room")
		await travel(current_scene.get_node("ReturnGate"))
		room = current_scene as Chapter1VineRoom
		check(player.position.distance_to(room.get_node("Portals/" + marker_name).position)<6, "boss return matches " + marker_name)
	player.set_physics_process(true)
	# Optional fast line: each canyon from a stable actual branch.
	await setup(Vector2(1500,620))
	check(await crossing(1640, "HighPerch", 1), "upper driven vine leads to high branch")
	if not room._standing_on(room.get_node("Terrain/HighPerch")): await setup(Vector2(2200,520))
	check(await crossing(2600, "UpperEast", 1), "upper long vine and relay cross central canyon")
	if not room._standing_on(room.get_node("Terrain/UpperEast")): await setup(Vector2(3300,650))
	check(await crossing(3640, "UpperExit", 1), "upper break vine crosses eastern canyon")
	await travel(room.get_node("Portals/WindGate"))
	check(current_scene.scene_file_path.ends_with("chapter_1_wind_room.tscn"), "vine to wind transition")
	await travel(current_scene.get_node("Portals/VineGate"))
	room = current_scene as Chapter1VineRoom
	check(room._standing_on(room.get_node("Terrain/WindRest")), "wind to vine uses current upper marker")
	await travel(room.get_node("Portals/RootGate"))
	check(current_scene.scene_file_path.ends_with("chapter_1_root_room.tscn"), "vine to root transition")
	await travel(current_scene.get_node("Portals/VineGate"))
	room = current_scene as Chapter1VineRoom
	check(room._standing_on(room.get_node("Terrain/RootRest")), "root to vine uses current lower marker")
	check(save_bytes == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "portal tests also preserve save bytes")
	print("VINE REMAKE CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)

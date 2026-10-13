extends "test_vine_sandbox.gd"

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	room = load("res://scenes/sideview/vine_swing_sandbox.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	player = room.player
	var platform: TerrainPiece = room.get_node("Terrain/GreenLaunch")
	platform._unregister_surface()
	platform.length = 900
	platform.register_to(player)
	var fixture := VineTrialPiece.new()
	fixture.name = "GroundContactVine"
	fixture.kind = "vine"
	fixture.position = Vector2(500, 700)
	fixture.vine_length = 380
	room.get_node("Terrain").add_child(fixture)
	fixture.register_to(player)
	await frames(15)
	clear_inputs()
	player.reset_after_map_fall(Vector2(390, 1000))
	player.play_run()
	drive(1)
	var caught_on_ground := false
	for i in 70:
		await physics_frame
		caught_on_ground = caught_on_ground or player.vine != null
	print("GROUND RUN ",player.position," caught=",caught_on_ground," state=",player.locomotion_state)
	check(not caught_on_ground and player.position.x > 550, "running through hanging vine on platform never catches")
	clear_inputs()
	player.set_physics_process(false)
	player.reset_after_map_fall(Vector2(500,1000))
	player.air_state = LanPlayer.AirState.FALLING
	player.velocity = Vector2(320,0)
	check(not player.try_start_vine(), "temporary FALLING state at ground support cannot catch")
	player.velocity.y = 10
	check(not player.try_start_vine(), "descending feet at platform cannot catch before landing")
	player.air_state = LanPlayer.AirState.RISING
	player.velocity.y = -300
	check(player.try_start_vine(), "intentional upward jump can catch at platform height")
	player.release_vine()
	player.set_physics_process(true)
	room.reset_station(0)
	fixture.vine_hold(0)
	player.reset_after_map_fall(Vector2(500,1000))
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	check(player.vine == fixture, "real jump input still catches overhead vine")
	clear_inputs()
	player.set_physics_process(false)
	if player.vine: player.release_vine()
	fixture.vine_hold(-0.8)
	var initial_radius := 1000.0 - fixture.position.y - LanPlayer.VINE_HAND_HEIGHT + 40.0
	player.start_vine(fixture, initial_radius)
	player.vine_omega = 1.2
	player.set_physics_process(true)
	var detached := false
	var penetrated := false
	var touched := false
	for i in 300:
		drive(signf(player.vine_omega) if absf(player.vine_omega) > 0.05 else 1)
		await physics_frame
		detached = detached or player.vine != fixture or player.air_state != LanPlayer.AirState.VINE_SWINGING
		penetrated = penetrated or player.position.y > 1000.01
		touched = touched or player.position.y >= 999.9
	check(touched and player.vine_radius < initial_radius, "swing reaches platform and takes up rope slack")
	check(not detached, "300 frames of swinging against ground retain held vine")
	check(not penetrated, "held swing feet never penetrate platform")
	clear_inputs()
	player.set_physics_process(false)
	fixture.vine_hold(0)
	player.start_vine(fixture, 1000.0-fixture.position.y-LanPlayer.VINE_HAND_HEIGHT)
	player.vine_omega = 0
	player.set_physics_process(true)
	Input.action_press(&"parry")
	await frames(5)
	check(player.vine == null and player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING], "K voluntarily releases at contact and lands normally with defense locked")
	clear_inputs()
	fixture.vine_hold(0)
	player.start_vine(fixture, 220)
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	check(player.vine == null, "W jump still voluntarily detaches")
	clear_inputs()
	check(save_bytes == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "player save bytes unchanged")
	print("VINE GROUND CONTACT: ", failures, " failures")
	quit(0 if failures == 0 else 1)

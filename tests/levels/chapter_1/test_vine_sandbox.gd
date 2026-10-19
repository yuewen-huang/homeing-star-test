extends SceneTree
## Real input tests + trajectory measurements. SaveProgress is replaced in memory.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(ability: StringName) -> bool:
		return ability != &"parry"

var room: Node2D
var player: LanPlayer
var failures := 0
var save_bytes: PackedByteArray
var rows: Array[String] = ["length_px,angle_deg,grip_px,speed_px_s,dx_px,dy_px,flight_s,pump_s"]

func _initialize() -> void:
	save_bytes = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func clear_inputs() -> void:
	for action in [&"ui_right", &"ui_left", &"jump", &"parry", &"ui_down"]:
		Input.action_release(action)

func drive(direction: float) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	if not is_zero_approx(direction):
		Input.action_press(&"ui_right" if direction > 0 else &"ui_left")

func route(index: int, target_name: String, limit := 1800, launch_override := "") -> bool:
	clear_inputs()
	room.reset_station(index)
	await frames(15)
	var launch: TerrainPiece = room.get_node("Terrain/" + ["GreenLaunch", "SwayLaunch", "BreakLaunch", "ReelLaunch"][index])
	var target: TerrainPiece = room.get_node("Terrain/" + target_name)
	if not launch_override.is_empty():
		launch = room.get_node("Terrain/" + launch_override)
		player.reset_after_map_fall(launch.position + Vector2(90, 0))
		await frames(15)
	drive(1)
	for i in 180:
		if player.position.x >= launch.position.x + launch.length - 50:
			break
		await physics_frame
	if index == 1:
		drive(0)
		var moving: VineTrialPiece = room.get_node("Terrain/FruitSway")
		for i in 240:
			if moving.vine_angle() < -0.4 and moving._vine_omega < 0:
				break
			await physics_frame
		drive(1)
	Input.action_press(&"jump")
	await frames(2)
	Input.action_release(&"jump")
	var grabbed := false
	var previous: TerrainPiece
	for i in limit:
		if player.vine != previous:
			print("GRIP ", index, " vine=", player.vine.name if player.vine else "none", " pos=", player.position, " velocity=", player.velocity)
			previous = player.vine
		if player.vine:
			grabbed = true
			if index == 0 and launch_override.is_empty():
				Input.action_press(&"ui_down")
			var ready := player.vine_angle > (0.75 if not launch_override.is_empty() else (0.5 if index != 3 else 0.65)) and player.vine_omega > 0 and absf(player.vine_omega * player.vine_radius) > (180 if index == 3 else (430 if not launch_override.is_empty() else 260))
			if index == 3:
				ready = ready and player.position.y < target.position.y - 20
			if not launch_override.is_empty():
				ready = ready and player.position.y < target.position.y - 30
			if ready:
				print("RELEASE ", index, " pos=", player.position, " radius=", player.vine_radius, " angle=", player.vine_angle, " speed=", absf(player.vine_omega * player.vine_radius))
				Input.action_release(&"ui_down")
				Input.action_press(&"parry")
				drive(1)
			else:
				drive(signf(player.vine_omega) if absf(player.vine_omega) > 0.08 else 1)
		else:
			drive(1)
		if player.position.x >= target.position.x + 35 and player.vine == null:
			drive(0)
			Input.action_press(&"parry")
		await physics_frame
		if absf(player.position.y - target.position.y) < 3 and player.position.x > target.position.x + 20 and player.position.x < target.position.x + target.length - 20:
			clear_inputs()
			return grabbed
		if player.position.y > 1355:
			break
	print("ROUTE END ", index, " ", player.position, " grabbed=", grabbed)
	clear_inputs()
	return false

func measure() -> void:
	# Only the measurement rig removes platforms/vines: actual-player integration,
	# no steering, flat receiving floor at the release height, outward pass.
	clear_inputs()
	player.set_physics_process(false)
	for piece in room.get_node("Terrain").get_children():
		piece.set_physics_process(false)
	player.ground_surfaces.clear()
	player.vines.clear()
	var vine: VineTrialPiece = room.get_node("Terrain/LongGreen")
	for radius in [240.0, 420.0, 650.0]:
		vine.vine_length = radius
		vine.position = Vector2(2700, 400)
		vine._vine_root = vine.position
		for angle in [20.0, 35.0, 50.0]:
			player.reset_after_map_fall(Vector2(2700, 400 + radius + 80))
			vine.reset_trial()
			player.start_vine(vine, radius)
			var released := false
			var build_ticks := 0
			for i in 2400:
				build_ticks += 1
				# Pump with the direction of motion: the same strategy as input routes.
				player.input_direction = signf(player.vine_omega) if absf(player.vine_omega) > 0.08 else 1
				player.update_vine_swing(1.0 / 60)
				if player.vine_angle >= deg_to_rad(angle) and player.vine_omega > 0 and absf(player.vine_omega * radius) > 350:
					released = true
					break
			check(released, "measurement reaches outward %.0f° at length %.0f" % [angle, radius])
			var origin := player.position
			var actual_angle := rad_to_deg(player.vine_angle)
			player.release_vine()
			var speed := player.velocity.length()
			var peak := origin.y
			player.register_ground_surface(Rect2(0, origin.y, 5400, 1))
			Input.action_press(&"parry")
			player.set_physics_process(true)
			var ticks := 0
			for i in 240:
				await physics_frame
				ticks += 1
				peak = minf(peak, player.position.y)
				if ticks > 5 and player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING]:
					break
			player.set_physics_process(false)
			rows.append("%.0f,%.1f,%.0f,%.1f,%.1f,%.1f,%.3f,%.3f" % [radius, actual_angle, radius, speed, player.position.x-origin.x, origin.y-peak, ticks/60.0, build_ticks/60.0])
			player.ground_surfaces.clear()
			clear_inputs()
	print("TRAJECTORY CSV\n", "\n".join(rows))
	var output := FileAccess.open((OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("vine_release_measurements.csv.txt")), FileAccess.WRITE)
	output.store_string("\n".join(rows) + "\n")

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var progress := MemoryProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	room = load("res://scenes/dev/vine_swing_sandbox.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	player = room.player
	await frames(20)
	check(await route(0, "GreenCatch"), "short green vine real-input crossing")
	check(await route(0, "LongCatch", 1800, "GreenCatch"), "long green vine real-input crossing to higher ledge")
	check(await route(1, "SwayCatch"), "driven vine real-input crossing")
	check(await route(2, "BreakCatch"), "break vine real-input crossing before timeout")
	check(await route(3, "ReelCatch"), "reel vine real-input upward crossing")
	clear_inputs()
	room.reset_station(2)
	player.set_physics_process(false)
	var brittle: VineTrialPiece = room.get_node("Terrain/CrackedBreak")
	player.start_vine(brittle, 400)
	player.vine_omega = 0.5
	await frames(80)
	check(brittle.broken and player.vine == null and not player.vines.has(brittle), "timeout releases and unregisters broken vine")
	check(player.velocity.length() > 100, "break preserves momentum")
	check(is_inf(brittle.vine_grab_point(brittle.vine_pivot() + Vector2(0, 400)).x), "broken vine cannot be grabbed")
	await frames(190)
	check(not brittle.broken and player.vines.has(brittle), "vine regrows and registers after 3 seconds")
	room.reset_station(3)
	player.set_physics_process(false)
	var reel: VineTrialPiece = room.get_node("Terrain/SpoolReel")
	player.start_vine(reel, 700)
	for i in 180:
		player.input_direction = 0
		player.update_vine_swing(1.0 / 60)
	check(is_equal_approx(player.vine_radius, reel.reel_stop_radius), "reel reaches configured stop without passing it")
	Input.action_press(&"parry")
	player.update_vine_swing(1.0 / 60)
	check(player.vine == null, "K releases while defense ability is locked")
	clear_inputs()
	room.reset_station(1)
	player.set_physics_process(false)
	var sway: VineTrialPiece = room.get_node("Terrain/FruitSway")
	var max_angle := 0.0
	for i in 120:
		await physics_frame
		max_angle = maxf(max_angle, absf(sway.vine_angle()))
	check(max_angle > 0.3, "empty driven vine keeps moving across its cycle")
	check(absf(sway.vine_catch_speed(400)) > 10, "driven vine supplies catch motion")
	room.reset_station(0)
	check(player.vine == null and not brittle.broken, "reset detaches and restores all vine types")
	player.set_physics_process(false)
	var green: VineTrialPiece = room.get_node("Terrain/LongGreen")
	green.vine_release(0.8, 0)
	await frames(600)
	check(absf(green.vine_angle()) < 0.02, "released green vine returns to rest instead of sleeping at a turning point")
	await measure()
	check(save_bytes == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "player save bytes unchanged")
	print("VINE SANDBOX CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)

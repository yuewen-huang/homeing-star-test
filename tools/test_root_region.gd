extends SceneTree

## Root water cavern behaviour checks. Drives the real player through every
## water level's route, the vein-lamp puzzle, the ledge treants and core entry.
## Each section starts from a fixed position and water level, so one failure
## does not cascade.
##
##   homeing-star-test/run-tests.ps1 -Test test_root_region
##
## Uses an in-memory SaveProgress fixture; real completion/checkpoints stay intact.

class FullProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var failures := 0
var room: Chapter1RootRoom
var player: LanPlayer
var water: RootWater


func _initialize() -> void:
	call_deferred("run_tests")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("  ok: ", message)


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func grounded() -> bool:
	return player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING,
		LanPlayer.AirState.ROLL_LANDING]


func on_y(y: float, tolerance := 4.0) -> bool:
	return grounded() and absf(player.position.y - y) <= tolerance


## Start a section: water level, logs on the surface, player standing at `at`.
func setup(at: Vector2, level: int) -> void:
	release_all()
	water.snap_to_level(level)
	for float_log in room._logs:
		float_log.snap_to_water()
	player.reset_after_map_fall(at)
	await frames(30)


func release_all() -> void:
	for action in [&"ui_left", &"ui_right", &"jump"]:
		Input.action_release(action)


func walk_to(x: float, limit := 900) -> void:
	var action := &"ui_right" if x > player.position.x else &"ui_left"
	Input.action_press(action)
	for i in limit:
		await physics_frame
		# Release early enough that the slide stops on the target.
		if absf(x - player.position.x) < 6.0 + absf(player.velocity.x) * 0.06:
			break
	Input.action_release(action)
	# Long enough that the next press is not read as a double tap (run).
	await frames(24)


## Jump and steer towards `target_x` like a player would: hold the direction
## while far from it, let go when above it. Double jump after `double_after`
## frames (0 = single); steer only after `steer_after` frames, so the player
## can rise past a ledge first.
func jump_to(target_x: float, double_after := 0, steer_after := 0, limit := 200) -> void:
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	for i in limit:
		if double_after > 0 and i == double_after:
			Input.action_press(&"jump")
		if double_after > 0 and i == double_after + 3:
			Input.action_release(&"jump")
		var dx := target_x - player.position.x
		var steer := i >= steer_after and absf(dx) > 10.0
		if steer and dx > 0.0:
			Input.action_release(&"ui_left")
			Input.action_press(&"ui_right")
		elif steer:
			Input.action_release(&"ui_right")
			Input.action_press(&"ui_left")
		else:
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
		await physics_frame
		if i > 8 and grounded():
			break
	release_all()
	await frames(24)


func wait_level(level: int, limit := 1200) -> void:
	for i in limit:
		await physics_frame
		if water.level == level and not water.is_moving():
			break
	await frames(30)


func attack_right() -> void:
	player.facing_direction = 1
	player.turn_target_direction = 1
	player.latest_pressed_direction = 1
	player.apply_facing_direction()
	player.start_attack_1x(1.0)
	await frames(50)


func run_tests() -> void:
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := FullProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	room = load("res://scenes/sideview/chapter_1_root_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	player = room.player
	water = room.water
	var progress := FullProgress.new()
	player.add_child(progress)
	player.save_progress = progress
	player.save_progress_resolved = true
	var save := root.get_node("SaveProgress") as SaveProgressService
	for id in [Chapter1RootRoom.PUZZLE_ID, Chapter1RootRoom.COMBAT_ID]:
		check(save.get_stele_state(id) == 0, "Root stele %s starts locked in isolated fixture" % id)
	await frames(5)
	var puzzle := room.get_node("Steles/PuzzleStele") as MinigameStele
	var combat := room.get_node("Steles/CombatStele") as MinigameStele
	var east_winch := room.get_node("Winches/WinchEastShore") as RootWaterWinch

	print("[entry]")
	check(player.position.distance_to(room.get_node("Portals/MistGate").position) < 2.0, "Mist arrival on MistGate marker")
	check(water.level == RootWater.MID and is_equal_approx(water.surface_y, 1240.0), "Water starts at the middle level")
	check(not room.has_node("Mechanisms/HeartSeal"), "Root-heart entrance has no progress seal")
	await walk_to(1400)
	check(on_y(1180), "Entrance steps lead down to the west shore: %s" % player.position)

	print("[middle level: log bridge from the west shore to the east shore]")
	await setup(Vector2(1500, 1180), RootWater.MID)
	var hops := [
		[1540, 1760, 0, 1226, "West shore -> first log"],
		[1880, 2160, 16, 1226, "First log -> pool log"],
		[2280, 2390, 0, 1190, "Pool log -> stone island"],
		[2470, 2660, 0, 1226, "Stone island -> middle log"],
		[2790, 3150, 16, 1226, "Middle log -> east pool log"],
		[3262, 3600, 16, 1226, "East pool log -> east log"],
		[3712, 3880, 0, 1180, "East log -> east shore"],
	]
	for hop in hops:
		await walk_to(hop[0])
		await jump_to(hop[1], hop[2])
		check(on_y(hop[3]) and absf(player.position.x - hop[1]) < 70.0, "%s: %s" % [hop[4], player.position])

	print("[pull and ride: middle -> high]")
	await setup(Vector2(3880, 1180), RootWater.MID)
	check(east_winch.pull(), "East-shore winch switches the water")
	check(water.target_level == RootWater.HIGH, "East-shore winch targets the high level")
	check(not east_winch.pull(), "Winch ignores a second pull while the water moves")
	await walk_to(3812)
	await jump_to(3640)
	check(grounded() and player.position.x > 3480 and player.position.x < 3720, "Stepped onto the east log in time: %s" % player.position)
	await wait_level(RootWater.HIGH)
	check(on_y(686, 6.0), "Log carried the player up to the high level: %s" % player.position)
	check(not (room.get_node("Logs/LogPoolEast") as RootFloatLog).is_standable(), "Tethered log stays under water")
	await walk_to(3705)
	await jump_to(3830, 12, 24)
	check(on_y(560) and player.position.x > 3760, "East log -> upper gallery: %s" % player.position)
	await walk_to(3900)
	check((room.get_node("Winches/WinchUpperGallery") as RootWaterWinch).pull(), "Gallery winch lowers the water")
	await wait_level(RootWater.MID)
	check(on_y(560), "Gallery stays dry while the water drops")

	print("[high level: west along the knots]")
	await setup(Vector2(3780, 560), RootWater.HIGH)
	await walk_to(3640)
	check(on_y(686, 6.0), "Gallery drop lands on the east log: %s" % player.position)
	var high_hops := [
		[3492, 3180, 26, 0, 560, "East log -> root-bridge knot"],
		[3015, 2700, 20, 0, 686, "Knot -> middle log"],
		[2585, 2330, 26, 6, 540, "Middle log -> crown knot"],
	]
	for hop in high_hops:
		await walk_to(hop[0])
		await jump_to(hop[1], hop[2], hop[3])
		check(on_y(hop[4], 6.0) and absf(player.position.x - hop[1]) < 80.0, "%s: %s" % [hop[5], player.position])
	var lamp_high := room.get_node("VeinLamps/LampHigh") as RootLightFungus
	await walk_to(2190)
	await attack_right()
	check(lamp_high.lit, "Normal attack lights the high vein lamp")
	var west_hops := [
		[2125, 1760, 26, 0, 686, "Crown -> west log"],
		[1675, 1380, 26, 6, 540, "West log -> west step"],
		[1312, 1150, 26, 40, 380, "West step -> heart ledge"],
	]
	for hop in west_hops:
		await walk_to(hop[0])
		await jump_to(hop[1], hop[2], hop[3])
		check(on_y(hop[4], 6.0) and absf(player.position.x - hop[1]) < 80.0, "%s: %s" % [hop[5], player.position])
	await walk_to(980, 200)
	check(player.position.x < 1060, "Vestibule is accessible before puzzle completion: %s" % player.position)

	print("[drown on rising water: retry from the shore]")
	await setup(Vector2(1500, 1180), RootWater.MID)
	check(room._checkpoint.y == 1180.0, "West shore became the checkpoint")
	water.request_level(RootWater.HIGH)
	for i in 400:
		await physics_frame
		if i > 200 and water.level == RootWater.MID and not water.is_moving():
			break
	await frames(20)
	check(water.level == RootWater.MID and not water.is_moving(), "Drowning reverted the water to the middle level")
	check(on_y(1180) and absf(player.position.x - 1500) < 60.0, "Respawned on the west shore: %s" % player.position)

	print("[low level: basin floor, root wall, sunken cave]")
	var fungus := room.get_node("Mechanisms/TunnelFungusOuter") as RootLightFungus
	check(fungus.submerged, "Tunnel fungus is under water at the middle level")
	fungus.receive_hit(1, Vector2.ZERO)
	check(not fungus.lit, "Submerged fungus cannot be lit")
	await walk_to(1250)
	check(puzzle.interact(), "Puzzle stele unlocks and saves")
	await walk_to(1500)
	check((room.get_node("Winches/WinchWestShore") as RootWaterWinch).pull(), "West-shore winch drains")
	await wait_level(RootWater.LOW)
	check(is_equal_approx(water.surface_y, 1910.0), "Water at the low level")
	check(not fungus.submerged, "Tunnel fungus above water at the low level")
	await walk_to(1640)
	await walk_to(2470)
	check(player.position.x > 2440 and on_y(1935), "Walked under the hanging stone: %s" % player.position)
	await jump_to(2600)
	await walk_to(2890)
	await walk_to(3240)
	await jump_to(3330)
	check(on_y(1890), "Pools and ridges cross to the east basin floor: %s" % player.position)
	await attack_right()
	check((room.get_node("VeinLamps/LampLow") as RootLightFungus).lit, "Low vein lamp lit at the low level")
	await walk_to(3830)
	check(on_y(1890), "Basin floor reaches the tunnel: %s" % player.position)
	var gate := room.get_node("Mechanisms/TunnelRootWall") as RootLightGate
	check(not gate.is_open, "Tunnel root wall closed")
	await walk_to(4000, 150)
	check(player.position.x < 3960, "Root wall blocks the tunnel: %s" % player.position)
	await setup(Vector2(3812, 1890), RootWater.LOW)
	await attack_right()
	check(fungus.lit and gate.is_open, "Attack lights the fungus and the root wall retracts")
	await walk_to(4450)
	check(on_y(1890), "Through the tunnel into the sunken cave: %s" % player.position)

	print("[combat stele]")
	await walk_to(4520)
	check(combat.interact(), "Combat stele unlocks")
	check(combat.interact() and room.combat_active, "Second E starts the combat challenge")
	check(not (room.get_node("Winches/WinchBasinFloor") as RootWaterWinch).pull(), "Winches lock during combat")
	var defeated := 0
	for i in 1800:
		await physics_frame
		for enemy in room._enemies:
			if is_instance_valid(enemy) and enemy.is_targetable():
				enemy.receive_hit(5, player.position)
				defeated += 1
		player.combat_stats.health = player.combat_stats.max_health
		if not room.combat_active:
			break
	check(defeated == 3, "Three ledge treants were spawned and defeated: %d" % defeated)
	check(combat.state == MinigameStele.SteleState.COMPLETED, "Combat stele completed")
	check(not east_winch.locked, "Winches unlock after combat")

	print("[shaft back to the east shore]")
	await setup(Vector2(4940, 1890), RootWater.LOW)
	var shaft := [
		[5060, 26, 16, 1760, "Floor -> shaft ledge 1"],
		[4925, 26, 0, 1630, "Ledge 1 -> ledge 2"],
		[5060, 26, 0, 1500, "Ledge 2 -> ledge 3"],
		[4925, 26, 0, 1380, "Ledge 3 -> ledge 4"],
		[5060, 26, 0, 1270, "Ledge 4 -> ledge 5"],
		[4820, 26, 0, 1180, "Ledge 5 -> east shore"],
	]
	for step in shaft:
		await jump_to(step[0], step[1], step[2])
		check(on_y(step[3]) and absf(player.position.x - step[0]) < 70.0, "%s: %s" % [step[4], player.position])

	print("[basin-floor winch: ride back up]")
	await setup(Vector2(1600, 1880), RootWater.LOW)
	check((room.get_node("Winches/WinchBasinFloor") as RootWaterWinch).pull(), "Basin-floor winch fills")
	await jump_to(1760)
	check(on_y(1846), "Stepped onto the resting log: %s" % player.position)
	await wait_level(RootWater.MID)
	check(on_y(1226, 6.0), "Log ride back up to the middle level: %s" % player.position)
	await walk_to(1670)
	await jump_to(1500)
	check(on_y(1180), "Back onto the west shore: %s" % player.position)

	print("[puzzle completion and unrestricted core entrance]")
	var lamp_mid := room.get_node("VeinLamps/LampMiddle") as RootLightFungus
	check(not lamp_mid.submerged, "Middle lamp above water at the middle level")
	await setup(Vector2(2340, 1190), RootWater.MID)
	await attack_right()
	check(lamp_mid.lit, "Middle vein lamp lit")
	await frames(5)
	check(puzzle.state == MinigameStele.SteleState.COMPLETED, "Three vein lamps complete the puzzle stele")
	check((room._portals[2].prompt as MapPortalPrompt).available, "Heart portal remains available independently of steles")
	await setup(Vector2(1200, 380), RootWater.HIGH)
	await walk_to(300)
	check(on_y(380) and player.position.x < 400, "Player can enter the unobstructed vestibule: %s" % player.position)

	print("[saved scene stays editable]")
	var packed := PackedScene.new()
	check(packed.pack(room) == OK, "Root room can be re-saved")
	room.queue_free()
	await process_frame
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Route regression preserves the real story save")
	print("Root region checks: %d failures" % failures)
	quit(1 if failures else 0)

extends "../../support/harness.gd"
## 第二章终关 · 水下沉城 graybox (step 1): scene loads, per-room camera limits tile the map,
## and the autopilot swims the main route R01 → R22 with real physics and input.
const SCENE_PATH := "res://scenes/levels/chapter_2_underwater/chapter_2_underwater.tscn"
const MAIN_ROUTE_ROOMS: Array[StringName] = [&"R01", &"R02", &"R03", &"R04", &"R07", &"R05", &"R06",
	&"R08", &"R09", &"R10", &"R12", &"R11", &"R18", &"R19", &"R20", &"R21", &"R23", &"R22"]

var level: Node2D


func run() -> void:
	use_memory_progress()
	await test_scene_loads()
	test_room_limits_tile_map()
	await test_camera_eases_between_rooms()
	await test_traversal()
	expect_save_untouched()
	finish("CHAPTER 2 UNDERWATER GRAYBOX")


func test_scene_loads() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "Scene loads: %s" % SCENE_PATH)
	level = packed.instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	await physics_frame
	await process_frame
	var map_size: Vector2 = level.MAP_SIZE
	check(map_size == Vector2(7680, 4320), "Map is 6x6 screens (7680x4320)")
	check(level.ROOMS.size() == 23, "23 rooms (layout_v2): %d" % level.ROOMS.size())
	check(level.player != null and level.player.is_inside_tree(), "Lan spawned")
	check(level.current_room == &"R01", "Starts in R01: %s" % level.current_room)
	check(level.camera.is_current(), "Room camera is current")
	check(level.camera_limits() == Rect2(0, 0, 1280, 720), "R01 camera limits: %s" % level.camera_limits())
	var walls := level.get_node("Terrain/Walls").get_child_count()
	var water := level.get_node("Water").get_child_count()
	check(walls > 30 and water >= 6, "Terrain built (%d walls, %d water volumes)" % [walls, water])
	for marker_name in ["Start", "BossRespawn", "GrandDoor", "KeyA", "KeyB", "PagodaGate", "WaterLever", "TopLock", "OneWayR17"]:
		check(level.has_node("Markers/" + marker_name), "Marker placeholder %s" % marker_name)


func test_room_limits_tile_map() -> void:
	var area := 0.0
	var rects: Array[Rect2] = []
	var ids := {}
	for room in level.ROOMS:
		var rect: Rect2 = level.room_rect(room)
		ids[room.id] = true
		check(rect.size.x >= 1280 and rect.size.y >= 720 and Rect2(Vector2.ZERO, level.MAP_SIZE).encloses(rect),
			"%s limits inside map, at least one screen: %s" % [room.id, rect])
		for other in rects:
			if rect.intersects(other, false):
				check(false, "%s limits overlap %s" % [room.id, other])
		rects.append(rect)
		area += rect.get_area()
	check(ids.size() == 23, "Room IDs unique")
	check(is_equal_approx(area, 7680.0 * 4320.0), "Room limits cover the whole map exactly (%.0f px²)" % area)
	var holes := 0
	for cy in 6:
		for cx in 6:
			if level.room_at(Vector2(cx * 1280 + 640, cy * 720 + 360)).is_empty():
				holes += 1
	check(holes == 0, "Every screen belongs to a room (holes %d)" % holes)


func test_camera_eases_between_rooms() -> void:
	var player: LanPlayer = level.player
	player.reset_after_map_fall(Vector2(1000, 1300))
	var seen := []
	for i in 90:
		await process_frame
		seen.append(level.camera_limits())
	var target := Rect2(0, 720, 1280, 1440)
	check(level.target_limits() == target, "R02 target limits: %s" % level.target_limits())
	var intermediate := seen.slice(0, 10).any(func(r): return r != target and r != Rect2(0, 0, 1280, 720))
	check(intermediate, "Limits ease (in-between values) instead of snapping")
	check(seen[-1] == target, "Limits settle on the new room: %s" % seen[-1])
	player.reset_after_map_fall(level.marker_position("Start"))
	level.snap_camera()
	await physics_frame


func test_traversal() -> void:
	var player: LanPlayer = level.player
	player.reset_after_map_fall(level.marker_position("Start"))
	level.snap_camera()
	await physics_frame
	var pilot: Node = level.start_autopilot(false)
	var frames := 0
	while not pilot.done and frames < 60 * 60 * 6:
		await physics_frame
		frames += 1
	check(pilot.done and pilot.success, "Autopilot reached the end of the route (%d/%d waypoints, %.1f s)" % [pilot.index, pilot.ROUTE.size(), frames / 60.0])
	check(level.current_room == &"R22", "Ends in R22 巨门前厅: %s" % level.current_room)
	check(player.position.distance_to(level.marker_position("BossRespawn")) < 80.0 and player.is_on_floor(),
		"Standing on the grand-door ledge: %s" % player.position)
	check(level.drowned_count == 0, "Autopilot never drowned (oxygen step 2): %d" % level.drowned_count)
	check(pilot.min_oxygen > 0.02, "Autopilot never emptied the oxygen bar (min %.2f)" % pilot.min_oxygen)
	for id in MAIN_ROUTE_ROOMS:
		check(id in pilot.visited, "Main route passes %s" % id)
	print("Rooms visited: %s" % [pilot.visited])

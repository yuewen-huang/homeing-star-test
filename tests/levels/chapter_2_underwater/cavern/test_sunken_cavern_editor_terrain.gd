extends "../../../support/harness.gd"
## Exercise the same save/reload path as a hand edit in Godot's 2D editor.

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TERRAIN_KEYS := ["walls", "smooth_walls", "floors", "platforms", "ramps", "ladders",
	"water", "doors", "well_east_scarp", "start", "markers", "visual_contours", "navigation"]


func run() -> void:
	use_memory_progress()
	var original: SunkenCavern = SCENE.instantiate()
	root.add_child(original)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SunkenCavern.LAYOUT_PATH))
	for key in TERRAIN_KEYS:
		check(original.layout[key] == expected[key], "The unedited scene preserves " + key)
	await wait_frames(2)
	check(not original.has_node("Terrain"), "Editor-only geometry and labels are removed during play")
	original.queue_free()
	await wait_frames(2)

	var edited: SunkenCavern = SCENE.instantiate()
	var foothold: ColorRect = edited.get_node("Terrain/Platforms/A4_Foothold")
	foothold.position += Vector2(10, -4)
	foothold.size.x += 24
	var wall: ColorRect = edited.get_node("Terrain/Rock/A4_RightWall")
	wall.position += Vector2(12, -8)
	wall.size.x += 6
	var slope: Line2D = edited.get_node("Terrain/Slopes/A1_EntranceSlope")
	slope.set_point_position(1, slope.get_point_position(1) + Vector2(8, -6))
	edited.get_node("Terrain/Slopes").get_child(0).free()
	var ladder: ColorRect = edited.get_node("Terrain/Ladders/Ladder_01")
	ladder.position.x += 16
	var water: ColorRect = edited.get_node("Terrain/Water/W2/Surface_01")
	water.position.y -= 12
	var latch: Marker2D = edited.get_node("Terrain/Gates/S1/Latch")
	latch.position.x -= 24
	var door: ColorRect = edited.get_node("Terrain/Gates/S1/Door")
	door.size.x += 16
	var anchor: Marker2D = edited.get_node("Terrain/Anchors/entry")
	anchor.position.x += 16
	var scarp: Polygon2D = edited.get_node("Terrain/EastScarp")
	scarp.position.x += 8
	var rocks := edited.get_node("Terrain/Rock")
	for i in 48:
		var block := ColorRect.new()
		block.name = "EditedRock%d" % i
		block.position = Vector2(156 + i % 12 * 48, 2190 + floori(float(i) / 12) * 44 + i % 12 * 3)
		block.size = Vector2(16, 12)
		rocks.add_child(block)
		block.owner = edited

	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern-editor")
	DirAccess.make_dir_recursive_absolute(output)
	var path := output.path_join("edited_cavern.tscn")
	var edited_scene := PackedScene.new()
	var saved := edited_scene.pack(edited) == OK and ResourceSaver.save(edited_scene, path) == OK
	edited.free()
	check(saved, "Godot saves the edited scene as a standalone scene resource")
	if not saved:
		finish("SUNKEN CAVERN EDITOR TERRAIN")
		return
	var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(loaded != null, "Godot reloads the saved scene")
	if not loaded:
		finish("SUNKEN CAVERN EDITOR TERRAIN")
		return
	var level: SunkenCavern = loaded.instantiate()
	root.add_child(level)
	await physics_frame
	await physics_frame

	check([3242.0, 3498.0, 176.0] in level.layout.platforms and [3232.0, 3502.0, 152.0] not in level.layout.platforms,
		"The edited foothold replaces its generated position and width")
	check([3404.0, 3318.0, 70.0] in level.layout.floors and [3392.0, 3326.0, 64.0] not in level.layout.floors,
		"The rock top moves with the wall")
	check(in_terrain_air(level, Vector2(3396, 3400)) and not in_terrain_air(level, Vector2(3464, 3400)),
		"The same edit moves the painted air boundary")
	check(not hits_rock(level, Vector2(3396, 3400)) and hits_rock(level, Vector2(3464, 3400)),
		"The removed wall is open and the newly occupied edge has real collision")
	check(level.layout.ramps[-1][1] == [1080.0, 2552.0], "The edited slope endpoint drives traversal")
	check(expected.ramps[0] not in level.layout.ramps and level.layout.ramps.size() == expected.ramps.size() - 1,
		"A deleted slope stays gone after reload")
	check(is_equal_approx(level.layout.ladders[0][0], expected.ladders[0][0] + 16), "The ladder moves in runtime data")
	var pool: UnderwaterVolume = level.get_node("LocalWater").get_child(3)
	check(pool.show_surface and is_equal_approx(pool.position.y, 2804.0), "The shifted W2 surface reaches the real swim volume")
	check(level.layout.doors[0].latch == [5288.0, 3932.0] and hits_rock(level, Vector2(5448, 3824)),
		"The S1 gate uses the saved latch and has the resized collision")
	check(level.start == Vector2(336, 2430) and level.player.position.distance_to(level.start) < 3,
		"Lan spawns at the saved entry marker")
	check(level.well_east_scarp[0] == Vector2(6152, 3200), "The special east rock face uses the saved polygon")
	var stone: ShaderMaterial = level.get_node("EntranceArt/PaintedFracturedRock").material
	var road: ShaderMaterial = level.get_node("EntranceArt/OldTradeRoad").material
	check(stone.get_shader_parameter("air_count") > 64 and stone.get_shader_parameter("contour_count") > 128
		and stone.get_shader_parameter("air_rects_table") is Texture2D and stone.get_shader_parameter("contour_edges_table") is Texture2D,
		"Denser edits retain all rock boundaries in the painting")
	check(road.get_shader_parameter("road_count") > 64 and road.get_shader_parameter("road_segments_table") is Texture2D,
		"Denser edits retain all real rock tops in the road painting")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("edited_cavern_render.png"))

	level.player.reset_after_map_fall(Vector2(3300, 3450))
	for i in 45:
		await physics_frame
	check(is_equal_approx(level.player.position.y, 3498.0), "Lan falls onto the edited foothold")
	expect_save_untouched()
	level.queue_free()
	await wait_frames(3)
	finish("SUNKEN CAVERN EDITOR TERRAIN")


func in_terrain_air(level: SunkenCavern, point: Vector2) -> bool:
	for box in level.layout.terrain_air:
		if level.rect(box).has_point(point):
			return true
	return false


func hits_rock(level: SunkenCavern, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not level.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()

extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TERRAIN_KEYS := ["walls", "smooth_walls", "floors", "platforms", "ramps",
	"ladders", "water", "doors", "well_east_scarp", "start", "markers", "visual_contours",
	"navigation", "mechanisms"]


func run() -> void:
	use_memory_progress()
	var authored: SunkenCavern = SCENE.instantiate()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SunkenCavern.LAYOUT_PATH))
	authored.get_node("Terrain").apply_to(expected)
	authored.free()
	var current: SunkenCavern = SCENE.instantiate()
	root.add_child(current)
	for key in TERRAIN_KEYS:
		check(current.layout[key] == expected[key], "Runtime preserves authored " + key)

	var solids := current.get_node("CavernRock")
	var boxes_match := true
	for index in expected.walls.size():
		var box: Array = expected.walls[index]
		var body := solids.get_child(index) as StaticBody2D
		var shape := body.get_child(0) as CollisionShape2D
		var rectangle := shape.shape as RectangleShape2D
		boxes_match = boxes_match and body.position == Vector2(box[0], box[1]) \
			and rectangle.size == Vector2(box[2], box[3]) and shape.position == rectangle.size * 0.5
	check(boxes_match, "Every runtime rectangular collider matches the hand-edited rock")
	var scarp := solids.get_node("WellEastScarp").get_child(0) as CollisionPolygon2D
	var expected_polygon := PackedVector2Array()
	for point in expected.well_east_scarp:
		expected_polygon.append(Vector2(point[0], point[1]))
	check(scarp.polygon == expected_polygon, "The east scarp polygon matches the authored points")
	var art := current.entrance_art.get_node("CavernMidground")
	check(art.get_child_count() == 9 and art.find_children("*", "CollisionObject2D", true, false).is_empty(),
		"Nine visual groups add zero collision objects")
	current.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("HAND-EDITED CAVERN GEOMETRY")

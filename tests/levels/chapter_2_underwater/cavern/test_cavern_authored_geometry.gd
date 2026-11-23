extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")

func run() -> void:
	use_memory_progress()
	var current: SunkenCavern = SCENE.instantiate()
	root.add_child(current)
	var expected: Array[Rect2] = []
	for room in current.get_node("Districts").get_children():
		for rock: Control in room.get_node("Geometry/Rock").get_children():
			expected.append(current.global_transform.affine_inverse() * rock.get_global_transform() * Rect2(Vector2.ZERO, rock.size))
	var solids := current.get_node("CavernRock")
	var boxes_match := solids.get_child_count() == expected.size()
	for index in mini(solids.get_child_count(), expected.size()):
		var box := expected[index]
		var body := solids.get_child(index) as StaticBody2D
		var shape := body.get_child(0) as CollisionShape2D
		var rectangle := shape.shape as RectangleShape2D
		boxes_match = boxes_match and body.position == box.position \
			and rectangle.size == box.size and shape.position == rectangle.size * 0.5
	check(boxes_match, "Every runtime rectangular collider matches the hand-edited rock")
	current.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("HAND-EDITED CAVERN GEOMETRY")

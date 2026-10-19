extends "../support/harness.gd"
## CombatHitQuery (restructure P4, 2026-10-19): the shared hurtbox rectangle that painted
## waves, spikes and walls test against. Must equal what each caller computed by hand before:
## centred on the shape's global position, its shape size, scale ignored.

func run() -> void:
	use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)
	var lan := Node2D.new()
	lan.position = Vector2(300, 555)
	world.add_child(lan)
	var hurtbox := CombatHurtbox2D.new()
	hurtbox.name = "Hurtbox"
	lan.add_child(hurtbox)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.position = Vector2(0, -43)
	collision.shape = RectangleShape2D.new()
	(collision.shape as RectangleShape2D).size = Vector2(40, 86)
	hurtbox.add_child(collision)

	var by_hand := Rect2(collision.global_position - Vector2(40, 86) * 0.5, Vector2(40, 86))
	check(CombatHitQuery.shape_rect(collision) == by_hand, "shape_rect is the old centre-minus-half-size rectangle (%s)" % str(CombatHitQuery.shape_rect(collision)))
	check(CombatHitQuery.hurtbox_rect(hurtbox) == by_hand, "hurtbox_rect accepts the hurtbox")
	check(CombatHitQuery.hurtbox_rect(lan) == by_hand, "hurtbox_rect accepts its owner")
	lan.scale = Vector2(2, 2)
	check(CombatHitQuery.shape_rect(collision).size == Vector2(40, 86), "Scale is ignored, as before")
	lan.scale = Vector2.ONE

	var rects := [Rect2(0, 0, 10, 10), Rect2(290, 500, 30, 30), Rect2(310, 520, 5, 5)]
	check(CombatHitQuery.first_overlap(rects, by_hand) == 1, "first_overlap finds the first touching rectangle")
	check(CombatHitQuery.first_overlap([Rect2(0, 0, 10, 10)], by_hand) == -1, "first_overlap is -1 when nothing touches")
	check(CombatHitQuery.first_overlap([], by_hand) == -1, "An empty list touches nothing")
	world.free()
	expect_save_untouched()
	finish("COMBAT HIT QUERY")

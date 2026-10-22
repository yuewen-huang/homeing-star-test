extends SceneTree
## Run with the smear-combo-demo project; visual trimming must not alter the sword path.

func _initialize() -> void:
	call_deferred("_run")

func _make(limit: float) -> SmearRibbon:
	var ribbon := SmearRibbon.new().configure({
		"look": &"blade", "duration": 0.15, "tail": 0.20, "width": 20.0,
		"reach": 1.08, "echo": false, "max_visible_turn": limit})
	ribbon.pose_keys.assign([
			{"u": 0.0, "hilt": Vector2.ZERO, "tip": Vector2(100, 0), "angle": 0.0},
			{"u": 1.0, "hilt": Vector2.ZERO, "tip": Vector2(0, 100), "angle": TAU * 1.25},
		])
	root.add_child(ribbon)
	ribbon.advance(0.15)
	return ribbon

func _run() -> void:
	var full := _make(0.0)
	var trimmed := _make(150.0)
	var full_vertices = full.blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var trimmed_vertices = trimmed.blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var okay: bool = trimmed_vertices.size() < full_vertices.size() and trimmed.samples.size() == full.samples.size()
	for time in [0.0, 0.04, 0.08, 0.12, 0.15]:
		okay = okay and full.blade_pose(time).tip.is_equal_approx(trimmed.blade_pose(time).tip)
	for point in [Vector2(50, 0), Vector2(0, 50), Vector2(-50, 0)]:
		okay = okay and full.swept_contains(point, 0.15) == trimmed.swept_contains(point, 0.15)
	var short_sword := _short_sword(false)
	var stable_band := _short_sword(true)
	var narrow: Dictionary = short_sword.blade_pose(0.075)
	var stable: Dictionary = stable_band.blade_pose(0.075)
	okay = okay and narrow.tip.is_equal_approx(stable.tip) and narrow.hilt.is_equal_approx(stable.hilt)
	okay = okay and stable.tip.distance_to(stable.inner) > narrow.tip.distance_to(narrow.inner) * 4.0
	for point in [Vector2(5, 0), Vector2(30, 0), Vector2(0, 50)]:
		okay = okay and short_sword.swept_contains(point, 0.15) == stable_band.swept_contains(point, 0.15)
	short_sword.free()
	stable_band.free()
	full.free()
	trimmed.free()
	if okay:
		print("PASS: visible arc cap and stable foreshortened band preserve measured blade poses and swept coverage")
	else:
		printerr("FAIL: visual arc cap changed the sword or failed to trim the mesh")
	quit(0 if okay else 1)

func _short_sword(stable: bool) -> SmearRibbon:
	var ribbon := SmearRibbon.new().configure({"duration": 0.15, "width": 75.0,
		"reference_blade_length": 100.0 if stable else 0.0, "reach": 1.08})
	ribbon.pose_keys.assign([
		{"u":0.0, "hilt":Vector2.ZERO, "tip":Vector2(12,0), "angle":0.0},
		{"u":1.0, "hilt":Vector2.ZERO, "tip":Vector2(12,0), "angle":0.0}])
	root.add_child(ribbon)
	return ribbon

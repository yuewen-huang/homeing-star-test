extends "../../support/harness.gd"
const DEPTH := preload("res://scripts/levels/chapter_2_underwater/city/city_terrain_depth.gd")

func run() -> void:
	var left := Rect2(0, 100, 100, 100)
	var right := Rect2(100, 100, 100, 100)
	var joined: Array[Rect2] = [left, right]
	check(DEPTH.right_spans(left, joined).is_empty(), "Adjacent floor pieces have no internal side cap")
	check(DEPTH.right_spans(right, joined) == [Vector2(100, 200)], "Only the exposed outside edge receives a side face")
	var ground := Rect2(0, 980, 1920, 100)
	var bank := Rect2(920, 770, 280, 210)
	var gate: Array[Rect2] = [ground, bank]
	check(DEPTH.top_spans(ground, gate) == [Vector2(0, 920), Vector2(1200, 1920)], "Lower floor top does not draw through the bank footprint")
	check(DEPTH.top_spans(bank, gate) == [Vector2(920, 1200)], "Bank keeps its complete existing walk range")
	var polygon := DEPTH.top_polygon(Vector2(920, 1200), 770)
	check(Geometry2D.is_point_in_polygon(Vector2(921, 770), polygon) and Geometry2D.is_point_in_polygon(Vector2(1199, 770), polygon), "Actual collision walk line stays inside the visible top plane")
	check(not Geometry2D.is_point_in_polygon(Vector2(918, 770), polygon) and not Geometry2D.is_point_in_polygon(Vector2(1202, 770), polygon), "Top plane does not invent support beyond either collision edge")
	var endpoint_a := DEPTH.top_polygon(Vector2(0, 100), 100)
	var endpoint_b := DEPTH.top_polygon(Vector2(100, 200), 100)
	check(endpoint_a[1] == endpoint_b[0] and endpoint_a[2] == endpoint_b[3], "Both depth vertices match exactly at a split floor seam")
	var touching := Rect2(1200, 850, 100, 130)
	var corner: Array[Rect2] = [bank, touching]
	check(DEPTH.right_spans(bank, corner) == [Vector2(770, 850)], "A lower adjoining step hides only the buried side interval")
	await wait_frames(3)
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.stop()
			node.stream = null
	await wait_frames(4)
	finish("CITY TERRAIN DEPTH")

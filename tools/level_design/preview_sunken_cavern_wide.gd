extends "../../tests/support/harness.gd"

const DESIGN_FILE := "homeing-star-doc/docs/design/sunken_cavern/wide_graybox.json"


func build_level() -> Node2D:
	var file := ProjectSettings.globalize_path("res://").path_join("../" + DESIGN_FILE).simplify_path()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not data is Dictionary:
		push_error("Wide cavern layout not found: " + file)
		return null
	var script_path := ProjectSettings.globalize_path("res://").path_join(
		"../homeing-star-test/tools/level_design/sunken_cavern_wide_preview_level.gd").simplify_path()
	var controller := load(script_path) as Script
	if controller == null:
		push_error("Wide cavern preview controller not found: " + script_path)
		return null
	var level: Node2D = controller.new()
	var progress := use_memory_progress()
	progress.try_complete_fact(level.CHAPTER_STORY.ROUTE)
	level.name = "SunkenCavernWide"
	level.source = data
	var enemies := Node2D.new()
	enemies.name = "ClockworkEnemies"
	level.add_child(enemies)
	for id: String in ["hidden_door", "hidden_return"]:
		var marker := Marker2D.new()
		marker.name = "A18HiddenDoor" if id == "hidden_door" else "A18HiddenReturn"
		marker.position = level.vector(level.source.markers[id])
		level.add_child(marker)
	root.add_child(level)
	current_scene = level
	return level


func run() -> void:
	var level := build_level()
	if not is_instance_valid(level) or not is_instance_valid(level.player):
		quit(1)
		return
	root.title = "归航星 · 沉没古城横向灰盒"
	print("SUNKEN_CAVERN_WIDE_READY")

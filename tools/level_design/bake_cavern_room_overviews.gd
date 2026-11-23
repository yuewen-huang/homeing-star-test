extends "../../tests/support/harness.gd"
## Render the authored rooms at rest, with no player or HUD. Each image belongs
## to one room; adjacent rooms and their layout transforms stay independent.
const MAP := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const OUTPUT := "res://assets/levels/chapter_2_underwater/cavern/editor_overviews/"
var canvas := SubViewport.new()
var map: SunkenCavern

func run() -> void:
	use_memory_progress()
	canvas.world_2d = World2D.new()
	canvas.transparent_bg = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	map = MAP.instantiate()
	canvas.add_child(map)
	map.process_mode = Node.PROCESS_MODE_DISABLED
	map.camera.enabled = false
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var original := {}
	for item in map.find_children("*", "CanvasItem", true, false):
		original[item] = [item.visible, item.self_modulate]
	for layer in map.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var rooms: Array[Node] = map.find_children("*", "Node2D", true, false).filter(func(node): return node.has_meta(&"room_footprint"))
	for room: Node2D in rooms:
		var path := str(map.get_path_to(room))
		for item: CanvasItem in original:
			var within := item == room or room.is_ancestor_of(item)
			item.visible = original[item][0] and (within or item.is_ancestor_of(room))
			item.self_modulate = original[item][1] if within else Color.TRANSPARENT
		for child: Node2D in rooms:
			if room.is_ancestor_of(child): child.hide()
		# District water volumes and refraction are created at map level. The viewport crops them to this room.
		if path.begins_with("Districts/"):
			var water := map.get_node("LocalWater")
			for item: CanvasItem in original:
				if item == water or water.is_ancestor_of(item) or item == map.get_node("WetSceneryCopy"):
					item.visible = original[item][0]
					item.self_modulate = original[item][1]
		# The continuous parallax river paints directly in the editor.
		if path == "ListeningEntry": room.get_node("CanalScenery").hide()
		var area: Rect2 = room.get_meta(&"room_footprint")
		canvas.size = Vector2i((area.size * 0.5).ceil())
		canvas.canvas_transform = Transform2D(0,Vector2(0.5,0.5),0,-room.to_global(area.position)*0.5)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := canvas.get_texture().get_image()
		if img == null or not img.get_used_rect().has_area():
			check(false, "Empty editor render: " + path)
			continue
		var file := path.get_file().to_snake_case() + ".webp"
		check(img.save_webp(OUTPUT + file, true, 0.92) == OK, file)
	expect_save_untouched()
	finish("CAVERN ROOM OVERVIEWS")

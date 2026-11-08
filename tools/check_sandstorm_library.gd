extends SceneTree

func _initialize() -> void:
	call_deferred("check_library")

func check_library() -> void:
	var lib = load("res://vfx/smear_library.gd").open("sandstorm_fighter")
	assert(lib.actions.size() == 17)
	var total := 0
	for action in lib.actions:
		for frame in lib.frame_numbers(action):
			assert(lib.texture(action, frame) != null)
			assert(lib.duration(action, frame) > 0)
			total += 1
	assert(total == 269)
	var editor = load("res://pose_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	assert(editor.library.id == "sandstorm_fighter")
	assert(editor.model.current().kind == "strike")
	print("PASS: 17 actions / 269 textures and timings; editor selects new character and fist track")
	editor.queue_free()
	await process_frame
	quit()

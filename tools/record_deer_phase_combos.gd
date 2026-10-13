extends SceneTree

var room
var output := ""

func _initialize() -> void:
	call_deferred("run")

func record(index: int, ticks: int) -> void:
	var folder := output.path_join("phase_%d" % (index + 1))
	DirAccess.make_dir_recursive_absolute(folder)
	room.select_combo(index)
	room.play_action(2)
	for frame in ticks:
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 3 == 0:
			var error := root.get_texture().get_image().save_png(folder.path_join("%03d.png" % (frame / 3)))
			if error != OK: quit(1); return
	print("PHASE ", index + 1, ": ", ticks / 3, " native frames")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	var first_phase := int(args[1]) if args.size() > 1 else 0
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	var durations := PackedInt32Array([330, 390, 480, 390])
	for index in range(first_phase, 4):
		await record(index, durations[index])
	current_scene = null
	room.free()
	quit()

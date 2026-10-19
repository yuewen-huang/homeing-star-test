extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
	# Inspect the authored environment without starting story or combat.
	room.set_script(null)
	room.get_node("Lan").process_mode = Node.PROCESS_MODE_DISABLED
	room.get_node("MasterBoss").process_mode = Node.PROCESS_MODE_DISABLED
	room.get_node("BossTargetDummy").hide()
	root.add_child(room)
	current_scene = room
	var camera := room.get_node("BattleCamera") as Camera2D
	var edge := float(camera.limit_right) - 640.0
	for sample in [["left", -edge], ["center", 0.0], ["right", edge]]:
		camera.position.x = sample[1]
		camera.reset_smoothing()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(sample[0] + ".png"))
	print("Captured master room: ", output)
	quit()

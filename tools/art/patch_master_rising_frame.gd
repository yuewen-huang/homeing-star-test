extends SceneTree
## One-frame art correction only. The live choreography and every other baked
## image stay unchanged. Reference: rift_dancer's sixth slash, ending at -160deg.
const PEAK := 1.0/3.0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.set_meta(&"master_vfx_baking",true)
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	if not FileAccess.file_exists(output.path_join("locked_manifest.json")):
		FileAccess.open(output.path_join("locked_manifest.json"),FileAccess.WRITE).store_string(MasterBakedEffect.LIBRARY.get_meta("manifest"))
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	for facing in [-1.0,1.0]:
		room.adapter._rebuild()
		var boss: MasterBoss = room.adapter.master
		boss.position.x = 640
		boss.set_process(false)
		boss.attack_hitbox.set_physics_process(false)
		room.adapter.target.position.x = 640+facing*200
		boss.start_clash_rhythm(&"inertia_combo")
		var rhythm = boss.clash_rhythm
		while rhythm.elapsed < 1.541: boss._process(1.0/240.0)
		var source: MasterTrajectoryRibbon = rhythm.winds[-1].node
		var poses: Array[Dictionary] = source.pose_keys.duplicate(true)
		var contact: Dictionary = poses[4]
		var extended: Dictionary = contact.duplicate()
		extended.u = PEAK/source.duration
		var rotation_delta: float = -float(facing)*deg_to_rad(114.0)
		var axis: Vector2 = ((contact.tip as Vector2)-(contact.hilt as Vector2)).rotated(rotation_delta)*1.30
		extended.tip = (extended.hilt as Vector2)+axis
		extended.angle = float(contact.angle)+rotation_delta
		poses.insert(5,extended)
		poses[-1] = extended.duplicate()
		poses[-1].u = 1.0
		source.pose_keys = poses
		source._curve_built = false
		source.reset()
		source.advance(PEAK)
		await process_frame
		await RenderingServer.frame_post_draw
		var viewport: SubViewport = source.get_child(0)
		viewport.get_texture().get_image().save_png(output.path_join("left.png" if facing < 0.0 else "right.png"))
	room.free()
	print("RISING SINGLE FRAME CAPTURED")
	quit()

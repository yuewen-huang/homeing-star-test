extends SceneTree
func _initialize() -> void: call_deferred("open_room")
func open_room() -> void:
	var root_phase := OS.get_cmdline_user_args().has("--root-phase")
	DisplayServer.window_set_title("鹿 · 第二阶段 / 争夺高台 · 根浪逼位" if root_phase else "鹿 · 第一阶段 / 连续攻势 · 破韧爆发")
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for index in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[index].adapter.resource_path.ends_with("deer_root_duel_adapter.gd" if root_phase else "deer_duel_adapter.gd"):
			room.select_boss(index)
			break
	await process_frame
	room.set_combat_simulation(true)
	print("DEER ROOT DUEL READY: contested summit, lowland root waves; real combat, isolated progress" if root_phase else "DEER DUEL READY: continuous phrases, independent leaves, sustained break reward; real combat, isolated progress")

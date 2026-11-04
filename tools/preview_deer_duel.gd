extends SceneTree
func _initialize() -> void: call_deferred("open_room")
func open_room() -> void:
	var root_phase := OS.get_cmdline_user_args().has("--root-phase")
	DisplayServer.window_set_title("鹿 · 第二阶段 / 根台 · 根脊 · 生台接横冲" if root_phase else "鹿 · 第一阶段 / 冲刺 · 常驻落叶 · 红刃反弹")
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
	print("DEER ROOT DUEL READY: five moves, two root layouts, drop-rush combo; real combat, isolated progress" if root_phase else "DEER DUEL READY: burst rush, persistent leaves, red leaf reflection; real combat, isolated progress")

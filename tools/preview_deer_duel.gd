extends SceneTree
func _initialize() -> void: call_deferred("open_room")
func open_room() -> void:
	var root_phase := OS.get_cmdline_user_args().has("--root-phase")
	var vine_phase := OS.get_cmdline_user_args().has("--vine-phase")
	var redraw := OS.get_cmdline_user_args().has("--rush-redraw")
	DisplayServer.window_set_title("鹿 · 第二阶段 / 争夺高台 · 根浪逼位" if root_phase else "鹿 · 第一阶段 / 连续攻势 · 破韧爆发")
	if vine_phase: DisplayServer.window_set_title("鹿 · 第三阶段 / 重踏爆藤 · 凌空落藤")
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for index in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[index].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd" if vine_phase else ("deer_root_duel_adapter.gd" if root_phase else "deer_duel_adapter.gd")):
			room.select_boss(index)
			break
	await process_frame
	room.set_combat_simulation(true)
	if redraw:
		DisplayServer.window_set_title("鹿 · 新造型横冲试玩 / 蓄力 · 突进 · 收势")
		room.combo_picker.select(1)
		room.select_combo(1)
		print("DEER RUSH REDRAW READY: real combat, repeated rush, isolated progress")
		return
	if vine_phase:
		if OS.get_cmdline_user_args().has("--vine-ground"):
			room.combo_picker.select(2)
			room.select_combo(2)
			print("DEER VINE GROUND READY: landing shake, outward light, delayed eruption, real combat")
		print("DEER VINE STORM READY: low return, stomp eruptions, distant caster and falling thorns; real combat, isolated progress")
		return
	print("DEER ROOT DUEL READY: contested summit, lowland root waves; real combat, isolated progress" if root_phase else "DEER DUEL READY: continuous phrases, independent leaves, sustained break reward; real combat, isolated progress")

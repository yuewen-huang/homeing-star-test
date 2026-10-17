extends SceneTree
## Unobstructed production-room samples of the five real wind strikes. No save writes.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var room := load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for node in room.find_children("*", "WindSightingComic", true, false): node.abandoned.emit()
	await process_frame
	await process_frame
	var deer: DeerBoss = room.deer
	if args.size() > 1: deer.clash_phase.smear_pixel_size = float(args[1])
	var lan: LanPlayer = room.player
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	deer.manual_control = true
	deer.phase = 3
	deer.position.x = 820.0
	deer.direction = -1.0
	lan.reset_after_map_fall(Vector2(655, 555))
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	for rhythm_id: StringName in [&"accel_five", &"red_finale"]:
		for i in 60: deer._physics_process(1.0 / 60.0)
		deer._recover(0.0)
		deer.start_clash(rhythm_id, lan.global_position.x)
		for strike: Dictionary in deer.clash_phase.rhythm.strikes:
			while deer.clash_phase.step_time < float(strike.t) + 0.015:
				deer._physics_process(1.0 / 60.0)
			if rhythm_id == &"red_finale" and strike.swing != "chop": continue
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s.png" % strike.swing))
			while deer.clash_phase.step_time < float(strike.t) + 0.12:
				deer._physics_process(1.0 / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s_fade.png" % strike.swing))
	room.free()
	quit()

extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.combo_picker.select(2)
	room.select_combo(2)
	room.set_playback_speed(2)
	room.set_combat_simulation(true)

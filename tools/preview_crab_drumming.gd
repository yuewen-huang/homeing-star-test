extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(8)
	room.select_combo_library(6)
	room.set_playback_speed(2)
	room.set_combat_simulation(true)

extends "../tests/support/harness.gd"
## Interactive sample: the existing development room owns combat and memory isolation.
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(1 if "--phase2" in OS.get_cmdline_user_args() else (4 if "--chop" in OS.get_cmdline_user_args() else 3))
	room.set_playback_speed(2)
	if "--combat" in OS.get_cmdline_user_args():
		room.set_combat_simulation(true)
	else:
		room.play_action(1 if "--triple" in OS.get_cmdline_user_args() else (2 if "--wind" in OS.get_cmdline_user_args() else 0))

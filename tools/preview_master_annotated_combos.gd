extends SceneTree
## Interactive production-room entry; the room itself isolates progress in memory.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.play_action(1)

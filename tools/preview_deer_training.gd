extends SceneTree
## Native playable slice; the development room isolates SaveProgress itself.
func _initialize() -> void: call_deferred("open_room")
func open_room() -> void:
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for index in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[index].adapter.resource_path.ends_with("deer_training_adapter.gd"):
			room.select_boss(index)
			break
	room.set_playback_speed(2)
	await process_frame
	room.set_combat_simulation(true)
	print("DEER TRAINING READY: four-move practice, real combat enabled, progress isolated")

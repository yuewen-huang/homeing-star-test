extends "../../support/harness.gd"
## Resource retirement must not break retained gameplay scenes or touch progress.

func run() -> void:
	use_memory_progress()
	for path in [
		"res://scenes/levels/chapter_2_underwater/chapter_2_underwater.tscn",
		"res://scenes/levels/chapter_2_underwater/tower/underwater_tower_foundation.tscn",
		"res://scenes/levels/chapter_2_underwater/city/sunken_city_gate.tscn",
	]:
		var packed := load(path) as PackedScene
		check(packed != null, "Scene resource loads: " + path.get_file())
		if packed == null: continue
		var level := packed.instantiate() as Node2D
		root.add_child(level)
		current_scene = level
		await wait_frames(8)
		check(is_instance_valid(level.player) and is_instance_valid(level.oxygen), "Player and oxygen survive art removal")
		check(level.player.combat_stats.health > 0, "Scene starts without player defeat")
		_stop_audio()
		level.queue_free()
		await wait_frames(8)
	_stop_audio()
	await wait_frames(4)
	expect_save_untouched()
	finish("RETIRED UNDERWATER ART SCENE LOADING")


func _stop_audio() -> void:
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.stop()
			node.stream = null

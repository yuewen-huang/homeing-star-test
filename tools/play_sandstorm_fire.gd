extends SceneTree
func _initialize()->void: call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var room:BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room);current_scene=room
	await process_frame
	room.select_combo(3)
	room.set_combat_simulation(true)
	room.player.position=Vector2(688,room.FLOOR_Y)
	room.adapter.boss.play_combat_combo("pressure")
	root.title="蝎女 · 炎劲拳脚实机预览"

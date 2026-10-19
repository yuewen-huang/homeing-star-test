extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	# Keep the room's camera code, but don't enter story or start combat.
	var room_script = room.get_script()
	room.set_script(null)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_script(room_script)
	var player = room.get_node("Lan")
	var boss = room.get_node("MasterBoss")
	var camera = room.get_node("BattleCamera")
	room.player = player
	room.boss = boss
	room.battle_camera = camera
	room._assert_battle_space_configuration()
	assert(camera.limit_left == -1280 and camera.limit_right == 1280)
	for actor in [player, boss]:
		assert(actor.world_min_x == -1184 and actor.world_max_x == 1184)
	for direction in [-1.0, 1.0]:
		player.position.x = direction * 1184.0
		room._update_battle_camera()
		assert(is_equal_approx(camera.position.x, direction * 640.0))
		assert(player.position.x >= camera.position.x - 640.0)
		assert(player.position.x <= camera.position.x + 640.0)
	player.ultimate_active = true
	player.position.x = -10000
	room._update_battle_camera()
	assert(is_equal_approx(camera.position.x, 640.0))
	var midground = room.get_node("Environment/Midground")
	assert(midground.get_child_count() == 2)
	for landscape in midground.get_children():
		assert(landscape.texture is AtlasTexture)
		assert(landscape.texture.atlas.resource_path.ends_with("04_midground_gardens_v1.png"))
		assert(is_equal_approx(landscape.scale.x, landscape.scale.y))
	print("Master room layout: two-screen bounds, camera edges and ultimate lock passed")
	quit()

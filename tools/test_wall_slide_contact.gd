extends SceneTree

## Real collision steps: sustained slide on both wall faces, release and jump.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	# Test progress is in memory only; never change the player's save file.
	var config := ConfigFile.new()
	config.set_value(SaveProgressService.PROGRESS_SECTION, String(SaveProgressService.TUTORIAL_MOVE), true)
	config.set_value(SaveProgressService.PROGRESS_SECTION, String(SaveProgressService.TUTORIAL_JUMP), true)
	var save := root.get_node("SaveProgress") as SaveProgressService
	save.set("_config", config)
	save.set("_loaded", true)
	var world := Node2D.new()
	root.add_child(world)
	var wall := StaticBody2D.new()
	wall.position = Vector2(640, 0)
	# Wind room S6_SlopeDown_78 uses this slight wall rotation.
	wall.rotation = 0.0042785
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 4000)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	for direction in [1.0, -1.0]:
		var player := preload("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
		player.world_min_x = 0
		player.world_max_x = 1280
		player.fallback_ground_y = 4000
		player.position = Vector2(640 - direction * 34 - tan(wall.rotation) * 171, 200)
		world.add_child(player)
		player.air_state = LanPlayer.AirState.FALLING
		player.play_air_animation(&"fall")
		var action := &"ui_right" if direction > 0 else &"ui_left"
		Input.action_press(action)
		var lost_slide := 0
		var max_speed := 0.0
		for i in 120:
			await physics_frame
			await process_frame
			if i > 10:
				if player.air_state != LanPlayer.AirState.WALL_SLIDING or player.animated_sprite.animation != &"wall_slide":
					lost_slide += 1
				max_speed = maxf(max_speed, player.velocity.y)
		check(lost_slide == 0, "face %s: uninterrupted slide, lost frames=%d" % [direction, lost_slide])
		check(max_speed <= LanPlayer.WALL_SLIDE_MAX_FALL_SPEED + 0.01, "slide speed stays capped: %.2f" % max_speed)
		Input.action_release(action)
		var away := &"ui_left" if direction > 0 else &"ui_right"
		Input.action_press(away)
		await physics_frame
		await process_frame
		check(player.air_state == LanPlayer.AirState.FALLING, "turn away releases slide immediately")
		Input.action_release(away)
		# Return to the wall and jump off after settling into a slide.
		Input.action_press(action)
		for i in 15:
			await physics_frame
			await process_frame
		Input.action_press(&"jump")
		await physics_frame
		await process_frame
		check(player.air_state == LanPlayer.AirState.RISING and player.velocity.x * direction < 0, "wall jump launches away")
		Input.action_release(&"jump")
		Input.action_release(action)
		player.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	await check_wind_wall()
	await check_entrance_wall_animation()
	quit(1 if failures else 0)

func check_entrance_wall_animation() -> void:
	var room := preload("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate() as Chapter1EmptyRoom
	root.add_child(room)
	await process_frame
	var wall := room.get_node("Terrain/S9_Wall_23") as TerrainPiece
	var player := room.player
	player.position = wall.position + Vector2(-12.1, 45)
	player.velocity = Vector2.ZERO
	player.air_state = LanPlayer.AirState.FALLING
	player.play_air_animation(&"fall")
	Input.action_press(&"ui_right")
	var min_hand_y := INF
	var max_hand_y := -INF
	var lost_slide := 0
	var seen_frames := {}
	for i in 45:
		await physics_frame
		await process_frame
		if i <= 5:
			continue
		if player.air_state != LanPlayer.AirState.WALL_SLIDING or player.animated_sprite.animation != &"wall_slide":
			lost_slide += 1
			continue
		var sprite := player.animated_sprite
		seen_frames[sprite.frame] = true
		var frame_image := sprite.sprite_frames.get_frame_texture(&"wall_slide", sprite.frame).get_image()
		if frame_image.is_compressed():
			frame_image.decompress()
		# First opaque pixel in the wall-side column is the hand, independently
		# measured from the artwork rather than the controller's offset table.
		for y in frame_image.get_height():
			if frame_image.get_pixel(0, y).a > 0.5:
				var hand_y := (float(y) + sprite.offset.y) * sprite.scale.y
				min_hand_y = minf(min_hand_y, hand_y)
				max_hand_y = maxf(max_hand_y, hand_y)
				break
	check(lost_slide == 0, "screenshot entrance wall: uninterrupted slide")
	check(seen_frames.size() == 3, "entrance wall samples the whole slide animation")
	check(max_hand_y - min_hand_y < 1.0, "wall hand stays anchored across loop: %.2f px" % (max_hand_y - min_hand_y))
	Input.action_release(&"ui_right")
	room.queue_free()
	await process_frame

func check_wind_wall() -> void:
	var room := preload("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate() as Chapter1EmptyRoom
	root.add_child(room)
	await process_frame
	var piece := room.get_node("Terrain/S6_SlopeDown_78") as TerrainPiece
	var player := room.player
	# Right face of the actual tilted wall, below its registered top surface.
	player.position = piece.position + Vector2(piece.size.x + 12.1, 45)
	player.velocity = Vector2.ZERO
	player.air_state = LanPlayer.AirState.FALLING
	player.play_air_animation(&"fall")
	Input.action_press(&"ui_left")
	var lost_slide := 0
	for i in 40:
		await physics_frame
		await process_frame
		if i > 5 and (player.air_state != LanPlayer.AirState.WALL_SLIDING or player.animated_sprite.animation != &"wall_slide"):
			lost_slide += 1
	check(lost_slide == 0, "actual wind room tilted wall: lost slide frames=%d" % lost_slide)
	Input.action_release(&"ui_left")
	await physics_frame
	await process_frame
	check(player.air_state == LanPlayer.AirState.FALLING, "releasing direction exits actual wind wall slide")
	room.queue_free()
	await process_frame

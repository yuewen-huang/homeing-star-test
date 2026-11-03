extends "../tests/support/harness.gd"
## Fixed input replay, production player, no save writes. --write-movie captures it.
var player: LanPlayer
var samples: Array = []
var frame := 0

func step(count: int) -> void:
	for i in count:
		await physics_frame
		frame += 1
		samples.append({"frame":frame,"x":player.position.x,"y":player.position.y,"vx":player.velocity.x,"vy":player.velocity.y,"air":player.air_state,"attack":player.attack_state,"clip":str(player.animated_sprite.animation)})

func release() -> void:
	for action in [&"ui_right",&"ui_left",&"jump",&"instant_dash"]: Input.action_release(action)

func place() -> void:
	release()
	player.reset_after_map_fall(Vector2(500,540))
	await step(12)

func run() -> void:
	use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(0,540),Vector2(1280,540),Vector2(1280,720),Vector2(0,720)])
	ground.color = Color("354950")
	world.add_child(ground)
	RenderingServer.set_default_clear_color(Color("17252e"))
	player = load("res://scenes/player/lan/lan_player.tscn").instantiate()
	player.world_min_x=40
	player.world_max_x=1240
	player.fallback_ground_y=540
	player.position=Vector2(500,540)
	world.add_child(player)
	await step(12)
	# Walk, run, reverse, stop.
	Input.action_press(&"ui_right")
	await step(6)
	Input.action_release(&"ui_right")
	await step(3)
	Input.action_press(&"ui_right")
	await step(30)
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(30)
	release()
	await step(24)
	# Air steering, then landing with direction held and a queued jump.
	await place()
	Input.action_press(&"jump")
	await step(12)
	Input.action_press(&"ui_right")
	await step(12)
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(12)
	Input.action_release(&"jump")
	await step(90)
	# Short versus full jump.
	await place()
	Input.action_press(&"jump")
	await step(3)
	Input.action_release(&"jump")
	await step(70)
	await place()
	Input.action_press(&"jump")
	await step(65)
	release()
	await step(12)
	# Late second jump, well after the falling clip's first four frames.
	await place()
	Input.action_press(&"jump")
	await step(34)
	Input.action_release(&"jump")
	await step(12)
	Input.action_press(&"jump")
	await step(65)
	release()
	await step(20)
	var out := OS.get_environment("LAN_CONTROL_OUTPUT")
	if out.is_empty(): out="res://../homeing-star-test/artifacts/lan_control_20261104/replay.json"
	var file := FileAccess.open(out,FileAccess.WRITE)
	file.store_string(JSON.stringify(samples))
	expect_save_untouched()
	finish("LAN CONTROL REPLAY")

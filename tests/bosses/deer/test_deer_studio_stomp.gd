extends SceneTree

var room
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("OK " if ok else "FAIL ", label)
	if not ok: failures += 1

func tick(count: int) -> void:
	for i in count:
		room.adapter.deer._physics_process(1.0 / 60.0)
		room._physics_process(1.0 / 60.0)
		room.adapter.deer.vfx._process(1.0 / 60.0)

func capture(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(label + ".png"))

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.play_action(0)
	tick(34)
	check(deer.vfx._stomp_quakes.is_empty(), "No effect before hoof contact")
	tick(2)
	check(deer.vfx._stomp_quakes.size() == 1 and deer.attack_hitbox.attack != null, "Light quake starts at real contact")
	var light: Node2D = deer.vfx._stomp_quakes[0]
	check(light.position.is_equal_approx(deer.position + Vector2(deer._anchor_offset(&"light_ING", 1, "hoof").x, 0)), "Quake anchored to hoof")
	tick(8)
	await capture("light")
	var age: float = light.age
	deer.vfx._process(0.05)
	check(is_equal_approx(light.age - age, 0.05 * deer.get_action_time_scale()), "Quake uses action clock")
	room.play_action(1)
	check(deer.vfx._stomp_quakes.is_empty(), "Restart clears quake")
	tick(85)
	check(deer.vfx._stomp_quakes.size() == 1 and deer.attack_hitbox.attack != null, "Heavy quake starts at real contact")
	tick(10)
	await capture("heavy")
	tick(180)
	check(deer.vfx._stomp_quakes.is_empty(), "Quake finishes and is removed")
	current_scene = null
	room.free()
	print("STUDIO STOMP failures: ", failures)
	quit(1 if failures else 0)

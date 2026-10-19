extends SceneTree

var room
var failures := 0
var checks := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("OK " if value else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60
		room.adapter.deer._physics_process(delta)
		room._physics_process(delta)
		room.adapter.deer.vfx._process(delta)

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	room.adapter.deer.vfx.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: output = args[0]; DirAccess.make_dir_recursive_absolute(output)
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
	check(deer.animated_sprite.frame == 0 and deer.attack_hitbox.attack == null, "F06 remains airborne with no damage")
	check(room.dummy.contacts.is_empty() and painted("light_stomp").is_empty(), "No premature dummy hit or dust")
	await snapshot("airborne")
	tick(2)
	check(deer.animated_sprite.frame == 1 and deer.attack_hitbox.attack != null, "F07 opens real hoof hitbox")
	check(deer.attack_collision.shape is CircleShape2D and is_equal_approx(deer.attack_collision.shape.radius, 160), "Light radius is exactly 2.5 development grid cells")
	check(deer.attack_collision.position.is_equal_approx(Vector2(deer._anchor_offset(&"light_ING",1,"hoof").x, 0)), "Light circle is centered on the planted hoof")
	var point := CircleShape2D.new()
	point.radius = 1
	var center: Vector2 = deer.attack_collision.global_position
	check(deer.attack_collision.shape.collide(deer.attack_collision.global_transform, point, Transform2D(0, center + Vector2(150, 0))) and not deer.attack_collision.shape.collide(deer.attack_collision.global_transform, point, Transform2D(0, center + Vector2(166, 0))) and not deer.attack_collision.shape.collide(deer.attack_collision.global_transform, point, Transform2D(0, center + Vector2(150, -150))), "Circle accepts inside range and rejects outside range and rectangle corners")
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].first_frame == 1, "Dummy first hit occurs on F07")
	check(painted("light_stomp").size() == 1 and painted("heavy_stomp").is_empty(), "Light uses dedicated local volume, not heavy waves")
	check(room.dummy.contacts[0].damage == 12, "Dummy receives actual 12-damage CombatAttackData")
	await snapshot("contact")
	tick(6)
	await snapshot("billow")
	tick(6)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].last_frame == 2, "One hit per segment; contact window ends at F08")
	check(deer.attack_hitbox.attack == null, "F09 closes damage")
	await snapshot("dissipate")
	tick(32)
	check(painted("light_stomp").is_empty(), "Painted light completes its authored timeline")
	room.dummy_x.value = 480
	room.play_action(0)
	tick(48)
	check(room.dummy.contacts.is_empty(), "Out-of-range wood cannot register a hit")
	room.dummy_x.value = 688
	room.play_action(0)
	tick(36)
	check(room.dummy.contacts.size() == 1, "Replay resets hit deduplication")
	var cloud = painted("light_stomp")[0]
	var age: float = cloud.elapsed
	deer.vfx._process(0.025)
	check(is_equal_approx(cloud.elapsed - age, 0.025 * deer.get_action_time_scale()), "VFX advances with combat action time")
	check(deer._anchor_offset(&"light_START",4,"hoof").y < deer._anchor_offset(&"light_ING",1,"hoof").y - 30, "Raised-hoof cue follows the moving hoof across independent clips")
	check(DeerPaintedArt.texture("light_stomp", "back") == DeerPaintedArt.texture("light_stomp", "back"), "Authored light atlas is cached and reused")
	check(DeerPaintedArt.frame_at("light_stomp",0.7).back != null, "Authored light contains its painted dust at 700 ms")
	room.play_action(0)
	check(room.dummy.contacts.is_empty() and painted("light_stomp").is_empty(), "Restart removes stale hits and effects")
	room.set_playback_speed(0)
	tick(136)
	check(room.dummy.contacts.is_empty() and painted("light_stomp").is_empty(), "Quarter speed cannot trigger impact before landing")
	tick(44)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].first_frame == 1 and room.dummy.contacts[0].last_frame == 2, "Quarter speed preserves F07-F08 contact window")
	room.set_playback_speed(2)
	room.dummy_x.value = 400
	room.play_action(1)
	tick(154)
	check(room.dummy.contacts.is_empty() and deer.vfx._waves.is_empty(), "Heavy no longer launches waves at a distant dummy")
	current_scene = null
	room.free()
	print("LIGHT STOMP: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func painted(kind: String) -> Array:
	return room.adapter.deer.vfx._painted.filter(func(effect: DeerPaintedEffect) -> bool: return effect.kind == kind)

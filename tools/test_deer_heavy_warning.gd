extends SceneTree

var room
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func advance(ticks: int) -> void:
	for tick in ticks:
		room.adapter.deer._physics_process(1.0 / 60)
		room.adapter.deer.vfx._process(1.0 / 60)
		room._physics_process(1.0 / 60)

func capture(name: String) -> void:
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
	room.play_action(1)
	advance(44)
	check(not deer.vfx.red_warning.visible, "Crouch does not display a persistent red sticker")
	await capture("windup")
	advance(8)
	check(deer.vfx.red_warning.visible and deer.vfx.red_warning.frame == 1, "Heavy warning opens the supplied resource")
	check(deer.vfx.red_warning.texture.resource_path.ends_with("red_counter_warning_625x87_5f.png"), "Exact user-supplied red warning texture")
	check(deer.vfx.red_warning.hframes == 5 and deer.vfx.red_warning.scale.is_equal_approx(Vector2.ONE * 2.8), "Five frames scaled uniformly for deer, not master size")
	check(is_zero_approx(deer.vfx._body_material.get_shader_parameter("warning")), "Red telegraph never tints the entire deer")
	await capture("opening")
	advance(4)
	check(deer.vfx.red_warning.visible and deer.vfx.red_warning.frame == 2, "Short warning reaches its bright frame without holding")
	check(deer.vfx.red_warning.position.distance_to(deer.position + deer.heavy_hoof_offset(deer.animated_sprite.frame)) < 2, "Warning follows the actual heavy hoof anchor")
	await capture("rearing")
	check(deer.heavy_hoof_offset(deer.animated_sprite.frame).y < deer.heavy_hoof_offset(0).y - 100, "Red warning flashes when the hoof is already raised")
	deer._parry_pause = 0.1
	var before: int = deer.vfx.red_warning.frame
	var at: Vector2 = deer.vfx.red_warning.position
	deer.vfx._process(0.05)
	check(deer.vfx.red_warning.frame == before and deer.vfx.red_warning.position == at, "Paused action cannot advance warning independently")
	deer._parry_pause = 0
	advance(6)
	check(deer.vfx.red_warning.frame == 3, "Warning uses resource release frame before impact")
	await capture("release")
	advance(6)
	check(not deer.vfx.red_warning.visible and deer.attack_hitbox.attack == null, "Warning disappears before unchanged landing time")
	await capture("charged")
	advance(18)
	check(deer.attack_hitbox.attack != null and not deer.vfx.red_warning.visible, "Real heavy damage activates without a body tint or lingering red marker")
	check(deer.attack_collision.shape is CircleShape2D and is_equal_approx(deer.attack_collision.shape.radius, 240), "Heavy PLUS radius is 1.5 times the light footprint")
	check(painted("heavy_stomp").size() == 1 and deer.vfx._waves.is_empty(), "Heavy produces one local impact and no traveling waves")
	var dust: DeerPaintedEffect = painted("heavy_stomp")[0]
	check(dust.back.z_index < deer.z_index + deer.animated_sprite.z_index and dust.front.z_index > deer.z_index + deer.animated_sprite.z_index, "Painted heavy layers enclose the body at their original depths")
	await capture("impact")
	advance(12)
	check(dust.back.visible, "Painted heavy back layer reaches its authored dust frame")
	await capture("billow")
	advance(92)
	check(not deer.vfx.red_warning.visible, "Recovery clears red warning")
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 20 and deer.vfx._waves.is_empty(), "Heavy lands once for 20 damage, without a follow-up wave hit")
	await capture("recovery")
	room.play_action(1)
	advance(52)
	check(deer.vfx.red_warning.frame == 1, "Restart replays red opening rather than retaining last frame")
	room.play_action(0)
	advance(1)
	check(not deer.vfx.red_warning.visible, "Switch to light removes heavy warning")
	room.play_action(1)
	advance(56)
	for frame in 5:
		deer._time = 0.8 + (frame + 0.5) / 16.0
		deer.vfx._update_red_warning()
		check(deer.vfx.red_warning.visible and deer.vfx.red_warning.frame == frame, "One-shot resource frame %d samples correctly" % frame)
	deer.vfx.reset_effects()
	check(not deer.vfx.red_warning.visible, "Reset removes the red warning immediately")
	current_scene = null
	room.free()
	print("HEAVY WARNING: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func painted(kind: String) -> Array:
	return room.adapter.deer.vfx._painted.filter(func(effect: DeerPaintedEffect) -> bool: return effect.kind == kind)

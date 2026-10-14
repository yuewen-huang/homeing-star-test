extends SceneTree

var room
var checks := 0
var failures := 0
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
	if not args.is_empty():
		output = args[0]
		DirAccess.make_dir_recursive_absolute(output)
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
	check(room.charge_button.visible and room.adapter.action_names().size() >= 4, "Development room exposes charge as action 4")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_4
	event.pressed = true
	room._unhandled_key_input(event)
	var start: Vector2 = deer.position
	var direction: float = deer.direction
	check(deer.state == DeerBoss.State.CHARGE and direction < 0, "Shortcut launches real charge toward the dummy")
	check(is_equal_approx(deer._charge_target, room.dummy.position.x + 100), "Charge stops in front of the locked target")
	tick(35)
	check(deer.position == start and deer.attack_hitbox.attack == null and room.dummy.contacts.is_empty(), "Windup has no movement or damage")
	check(not deer.vfx.gold_warning.visible, "No gold flash before its cue")
	tick(7)
	check(deer.vfx.gold_warning.visible and deer.vfx.gold_warning.frame == 1, "Gold plays the supplied five-frame resource once")
	check(deer.vfx.gold_warning.texture.resource_path.ends_with("gold_unparryable_warning_625x87_5f.png"), "Gold uses its dedicated asset, not the red texture or a line diamond")
	check(deer.vfx.gold_warning.position.distance_to(deer.vfx.chest().snapped(Vector2(2, 2))) < 0.01, "Gold cue plays on the chest light (2026-10-14: all danger cues on the chest)")
	check(deer.vfx._body_material.get_shader_parameter("warning") == 0.0 and deer.animated_sprite.modulate.a == 1.0, "Development warning leaves body colors intact and specimen visible")
	await snapshot("warning")
	tick(16)
	check(not deer.vfx.gold_warning.visible and deer.position == start, "Gold flash ends before the charge and never holds its last frame")
	tick(17)
	check(deer.position.x < start.x and is_instance_valid(deer.vfx._painted_rush), "Rush moves physically with the authored painted rush")
	check(deer.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER, "Rush is gold and cannot offer parry QTE")
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 18, "Dummy samples exactly one 18-damage rush contact")
	check(deer.vfx._trails.is_empty(), "Regular charge no longer stacks full-body ghosts")
	await snapshot("rush")
	while deer._segment == 0: tick(1)
	check(is_equal_approx(deer.position.x, deer._charge_target) and deer.direction == direction, "Charge brakes before the dummy without turning around")
	check(deer.animated_sprite.frame == 0 and deer.attack_hitbox.attack == null and is_instance_valid(deer.vfx._painted_uppercut), "F18 starts the real uppercut volume before opening its hitbox")
	tick(6)
	await snapshot("uppercut_sweep")
	check(deer.animated_sprite.frame == 1 and room.dummy.contacts.size() == 1, "Rising F19 does not open uppercut damage early")
	tick(4)
	check(deer.animated_sprite.frame == 0 and room.dummy.contacts.size() == 2, "F20 opens the separate uppercut contact")
	check(room.dummy.contacts[1].damage == 22 and deer.attack_hitbox.attack.launch_velocity == -340, "Uppercut delivers 22 damage and launch data")
	check(room.dummy.contacts[1].key != room.dummy.contacts[0].key and room.dummy.contacts[1].first_time > room.dummy.contacts[0].first_time, "Both segments have unique IDs and cumulative charge timestamps")
	await snapshot("uppercut_contact")
	tick(16)
	check(deer.attack_hitbox.attack == null and room.dummy.contacts[1].last_frame == 2, "Uppercut damage closes at F23")
	tick(180)
	check(deer.state == DeerBoss.State.IDLE and room.dummy.contacts.size() == 2, "Skill ends with two hits and manual idle")
	check(deer.vfx._painted.is_empty(), "Recovery clears all painted layers")
	await snapshot("recovery")
	room.dummy_x.value = 1000
	room.play_action(3)
	tick(100)
	check(deer.direction > 0 and room.dummy.contacts.size() == 2, "Mirrored charge still reaches both real contacts")
	await snapshot("mirrored")
	room.play_action(3)
	tick(40)
	var locked: float = deer._charge_target
	room.dummy_x.value = 800
	tick(80)
	check(is_equal_approx(deer._charge_target, locked) and deer.direction > 0, "Moving the target after windup cannot steer or reverse the charge")
	room.dummy_x.value = 688
	room.play_action(3)
	room.set_playback_speed(0)
	tick(239)
	check(deer._segment < 0 and room.dummy.contacts.is_empty(), "Quarter speed preserves the entire windup")
	tick(201)
	check(room.dummy.contacts.size() == 2 and room.dummy.contacts[1].first_frame == 0, "Quarter speed preserves both contacts and the uppercut frame")
	room.set_playback_speed(2)
	room.play_action(3)
	tick(88)
	check(is_instance_valid(deer.vfx._painted_uppercut) and deer.vfx._painted_uppercut.back.visible, "Uppercut back layer is present during the actual antler lift")
	deer.enter_stagger(2)
	check(deer.vfx._painted.is_empty(), "Interrupting the lift clears both uppercut layers immediately")
	room.play_action(3)
	tick(75)
	deer.enter_stagger(2)
	check(deer.vfx._painted.is_empty() and not deer.vfx.gold_warning.visible, "Interrupt clears rush effects and gold cue")
	tick(100)
	check(room.dummy.contacts.size() == 1, "Interrupted rush cannot produce a delayed uppercut")
	room.play_action(0)
	check(deer.position == Vector2(820, 555) and deer.state == DeerBoss.State.LIGHT, "Returning to light restores its accepted development position")
	check(DeerPaintedArt.frame_at("charge_uppercut", 1.0).back != null, "Rush samples the authored back layer")
	check(DeerPaintedArt.frame_at("charge_uppercut", 1.6).front != null, "Lift samples the authored blue front layer")
	check(DeerPaintedArt.frame_at("charge_uppercut", 2.9).front == null, "Authored lift finishes without retaining its last painted cel")
	current_scene = null
	room.free()
	print("DEER CHARGE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

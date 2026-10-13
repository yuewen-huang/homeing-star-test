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
	check(room.combo_button.visible and room.adapter.action_names().size() >= 3, "Deer exposes the third development action")
	room.play_action(2)
	check(deer.combo_step == 0 and deer.state == DeerBoss.State.LIGHT, "Combo starts with real light action")
	tick(19)
	check(deer.animated_sprite.frame == 0 and room.dummy.contacts.is_empty(), "Fast F06 is still airborne with no premature hit")
	await snapshot("fast_warning")
	tick(1)
	check(deer.animated_sprite.frame == 1 and room.dummy.contacts.size() == 1, "Fast contact opens at F07 around 0.333 seconds")
	check(painted("light_stomp").size() == 1 and deer.attack_collision.shape.radius == 160, "Fast hit retains accepted light mist and radius")
	check(room.dummy.contacts[0].damage == 12, "Fast hit deals 12 once")
	await snapshot("fast_impact")
	tick(5)
	await snapshot("fast_billow")
	tick(9)
	check(deer.combo_step == 0 and deer.attack_hitbox.attack == null, "Fast hitbox closes before the linked knife")
	check(room.dummy.contacts[0].last_frame == 2, "Fast damage window stays on F07-F08")
	tick(1)
	check(deer.combo_step == 1 and deer.state == DeerBoss.State.HEAVY, "Fast light links directly into heavy without idle or recovery")
	check(is_zero_approx(deer._time) and deer.combo_elapsed > 0.57, "Linked action resets local time but keeps combo time")
	tick(75)
	check(deer.animated_sprite.frame == 16 and deer.vfx.red_warning.visible, "Slow knife holds raised F16 and gives one red flash")
	await snapshot("slow_warning")
	tick(21)
	check(deer.animated_sprite.frame == 16 and deer.attack_hitbox.attack == null, "Extra hold does not interpolate into falling frames or damage")
	check(not deer.vfx.red_warning.visible and room.dummy.contacts.size() == 1, "Red flash ends during hold without looping or extra contact")
	await snapshot("slow_hold")
	tick(14)
	check(deer.animated_sprite.frame == 17 and painted("heavy_stomp").is_empty(), "Slow F17 remains airborne with no PLUS dust")
	tick(2)
	check(deer.animated_sprite.frame == 0 and room.dummy.contacts.size() == 2, "Slow F18 lands once after the delay")
	check(deer.attack_collision.shape.radius == 240 and painted("heavy_stomp").size() == 1 and deer.vfx._waves.is_empty(), "Slow knife reuses local PLUS mist, not ground waves")
	check(room.dummy.contacts[1].damage == 20 and room.dummy.contacts[0].key != room.dummy.contacts[1].key, "Both knives have separate real attack IDs and 12/20 damage")
	check(room.dummy.contacts[1].first_time > 2.4 and room.dummy.contacts[1].first_time < 2.46, "Dummy timestamps use cumulative combo time")
	await snapshot("slow_impact")
	tick(7)
	await snapshot("slow_billow")
	tick(160)
	check(deer.combo_step == -1 and deer.state == DeerBoss.State.IDLE, "Whole combo returns to manual idle")
	check(room.dummy.contacts.size() == 2 and painted("heavy_stomp").is_empty() and deer.attack_hitbox.attack == null, "Recovery has no third hit or residual impact")
	await snapshot("recovery")
	room.play_action(2)
	tick(8)
	deer.interrupt_with_special()
	tick(180)
	check(deer.combo_step == -1 and room.dummy.contacts.is_empty(), "Special interruption cancels pending follow-up")
	room.play_action(2)
	tick(110)
	deer.enter_stagger(2)
	tick(20)
	check(deer.combo_step == -1 and deer.state == DeerBoss.State.STAGGER and room.dummy.contacts.size() == 1, "Stagger during slow hold cancels the second knife")
	deer.reset_phase()
	deer.position = room.BOSS_START
	room.play_action(2)
	tick(35)
	room.play_action(0)
	check(deer.combo_step == -1 and is_equal_approx(deer._action_speed, 1), "Replaying standalone light clears combo speed and delayed follow-up")
	tick(34)
	check(room.dummy.contacts.is_empty(), "Standalone light keeps its accepted original timing")
	tick(2)
	check(room.dummy.contacts.size() == 1, "Standalone light lands at its original F07")
	room.play_action(2)
	room.set_playback_speed(0)
	tick(79)
	check(room.dummy.contacts.is_empty(), "Quarter-speed combo cannot hit before its fast landing")
	tick(1)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].first_frame == 1, "Quarter-speed combo retains contact frame")
	tick(510)
	check(room.dummy.contacts.size() == 2 and room.dummy.contacts[1].first_frame == 0, "Quarter speed scales the complete slow hold and landing")
	room.set_playback_speed(2)
	check(not deer.start_combo(&"missing") and deer.combo_step == 1, "Unknown variant cannot corrupt the active combo")
	var adapter = room.adapter
	room.adapter = load("res://scripts/dev/boss_development_adapter.gd").new()
	room.dummy.begin_action()
	room.play_action(2)
	check(room.dummy.contacts.is_empty(), "Third shortcut is ignored for a boss without a combo")
	room.adapter = adapter
	current_scene = null
	room.free()
	print("STOMP COMBO: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func painted(kind: String) -> Array:
	return room.adapter.deer.vfx._painted.filter(func(effect: DeerPaintedEffect) -> bool: return effect.kind == kind)

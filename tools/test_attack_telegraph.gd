extends SceneTree
## Integration regression for shared warnings, using the real development-room attacks.
## -- --capture <directory> additionally renders warning / active / recovery states.
var room
var deer: DeerBoss
var failures := 0
var checks := 0
var output := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--capture":
		output = args[1]
		DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func count_marks(warning: AttackTelegraph) -> int:
	var count := 0
	for child in warning.get_children():
		if child is Sprite2D and child.visible: count += 1
	return count

func shot(label: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(), "Rendered viewport: " + label)
	image.save_png(output.path_join(label + ".png"))

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.select_combo(4)
	room.play_action(0)
	for i in 600:
		if deer.vine_phase.step == DeerVinePhase.Step.HOVER: break
		deer._physics_process(1.0 / 60.0)
	check(deer.vine_phase.human, "Real fourth-phase transformation completes")
	var vine := deer.vine_phase
	for kind: StringName in [&"pierce", &"pierce_red", &"ground_lash", &"curtain"]:
		var strike := vine.spawn_strike(kind, room.dummy.position.x, deer.position.x, 0.8, Vector2(950, 260))
		check(count_marks(strike._telegraph) > 0, "%s: visible from cast start" % kind)
		var mark := strike._telegraph.get_child(0) as Sprite2D
		var initial_transform := mark.transform
		strike.step(0.4)
		check(mark.transform.is_equal_approx(initial_transform), "%s: countdown never resizes/moves the committed footprint" % kind)
		var before := float((mark.material as ShaderMaterial).get_shader_parameter("progress"))
		strike.step(0.0)
		check(is_equal_approx(before, float((mark.material as ShaderMaterial).get_shader_parameter("progress"))), "%s: zero action delta freezes warning" % kind)
		strike.step(0.1)
		check(is_equal_approx(float((mark.material as ShaderMaterial).get_shader_parameter("progress")), 0.625), "%s: supplied quarter-speed delta advances the same clock" % kind)
		await shot("%s_warning" % kind)
		strike.step(0.35)
		if kind == &"curtain": strike.step(strike.travel_time() * 0.65)
		elif kind == &"ground_lash": strike.step(1.45)
		else: strike.step(0.08)
		await shot("%s_active" % kind)
		strike.cancel()
		check(not strike.is_visible_in_tree(), "%s: cancel immediately hides warning with the attack" % kind)
		await shot("%s_recovery" % kind)
		strike.queue_free()
		await process_frame
	var red := vine.spawn_strike(&"pierce_red", 688, 820, 0.8, Vector2(950, 260))
	red.snap()
	check(count_marks(red._telegraph) == 0, "Counter-parry immediately clears the remaining warning")
	red.cancel()
	red.queue_free()
	var root_volley := DeerRootVolley.new()
	deer.add_child(root_volley)
	root_volley.top_level = true
	root_volley.global_position = Vector2.ZERO
	root_volley.setup(555, room.player.hurtbox, deer, CombatAttackData.new(&"warning_regression", deer, 0, 0, 0, 0, CombatAttackData.DangerType.UNPARRYABLE_DANGER))
	root_volley.no_player_damage = true
	root_volley.add_root(550, 0.0, 0.8, "short1", false)
	root_volley.add_root(740, 0.3, 1.2, "short1", false)
	root_volley.step(0.1)
	check(count_marks(root_volley._telegraph) == 1, "Staggered roots expose only warnings whose own lead-in started")
	root_volley.step(0.3)
	check(count_marks(root_volley._telegraph) == 2, "Root volley shares one renderer across simultaneous marks")
	await shot("roots_warning")
	root_volley.step(0.45)
	check(count_marks(root_volley._telegraph) == 1, "First erupted root clears without clearing the next root's warning")
	await shot("roots_active")
	root_volley.cancelled = true
	check(count_marks(root_volley._telegraph) == 0, "Direct phase cancellation clears root warning children immediately")
	await shot("roots_recovery")
	root_volley.queue_free()
	# A lethal contact cancels all encounter roots while step() is still unwinding.
	var reentrant := CancelOnContactVolley.new()
	deer.add_child(reentrant)
	reentrant.set_process(false)
	reentrant.add_root(550, 0.0, 0.8, "short1", false)
	reentrant.no_player_damage = true
	reentrant.step(0.1)
	check(count_marks(reentrant._telegraph) == 1, "Contact-cancellation probe starts with an actual warning")
	reentrant.no_player_damage = false
	reentrant.step(0.1)
	check(reentrant.cancelled and count_marks(reentrant._telegraph) == 0, "Synchronous contact cancellation cannot recreate a cleared warning")
	reentrant.queue_free()
	room.select_boss(0)
	await process_frame
	check(not is_instance_valid(red) and not is_instance_valid(root_volley), "Changing specimens frees attack-owned warning nodes")
	# The four core action libraries use oriented regions and cancellable decoys.
	for region_index in range(4, 8):
		room.select_boss(region_index)
		var core: RegionalCoreBoss = room.adapter.core
		core.set_physics_process(false)
		for action_index in 2:
			core.start_action(action_index, Vector2(688, 555))
			check(count_marks(core.effects._telegraph) > 0, "Core %d action %d: shares range renderer" % [region_index, action_index])
			await shot("core_%d_action_%d_warning" % [region_index, action_index])
			core.cancel_action()
			check(count_marks(core.effects._telegraph) == 0, "Core %d action %d: cancellation clears warning and decoys" % [region_index, action_index])
	print("ATTACK_TELEGRAPH: %d checks, %d failures" % [checks, failures])
	room.queue_free()
	await process_frame
	quit(1 if failures else 0)

class CancelOnContactVolley extends DeerRootVolley:
	func _resolve_hit() -> void:
		cancelled = true

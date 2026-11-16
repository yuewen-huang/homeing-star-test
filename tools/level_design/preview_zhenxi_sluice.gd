extends "../../tests/support/harness.gd"
## Playable section from the submerged approach to the rear of the shadow wall.

class Sluice extends ZhenxiSluiceSection:
	const PLAYER := preload("res://scenes/player/lan/lan_player.tscn")
	const TITLE := "归航星 · 镇西门 · 穿过疑兵"
	const APPROACH := Vector2(209, 274)

	func _ready() -> void:
		lan = PLAYER.instantiate() as LanPlayer
		lan.z_as_relative = false
		lan.world_min_x = PLAY_LEFT
		lan.world_max_x = PLAY_RIGHT
		lan.fallback_ground_y = LOWER_DECK.end.y + 48.0
		lan.prevent_roll_off_edges = true
		add_child(lan)
		lan.get_node("PlayerStatusHUD").hide()
		lan.get_node("SkillBar").hide()
		super._ready()
		activate()
		reached_rear_exit.connect(func(): get_window().title = TITLE + " · 已到达幕背出口")

	func reset(at := SPAWN) -> void:
		super.reset(at)
		lan.combat_stats.restore_health()
		get_window().title = TITLE

	func _unhandled_input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key == null or not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_R:
				reset()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				get_tree().quit()


class RouteInput extends RefCounted:
	var _tree: SceneTree

	func _init(tree: SceneTree) -> void:
		_tree = tree


	func leave_pool(level: ZhenxiSluiceSection, observe_bank := Callable()) -> bool:
		Input.action_press(&"ui_up")
		await walk_right(level, -310.0, 150)
		for frame in 150:
			if level.lan.swim.floating:
				break
			await step(1)
		Input.action_release(&"ui_up")
		if not level.lan.swim.floating:
			print("Expected surface float, Lan at %s in state %d" % [level.feet(), level.lan.air_state])
			return false
		await step(2)
		await jump_right(70)
		if observe_bank.is_valid():
			await observe_bank.call()
		await walk_right(level, Sluice.APPROACH.x, 135)
		if level.feet().x < Sluice.APPROACH.x:
			print("Expected approach, Lan at %s in state %d" % [level.feet(), level.lan.air_state])
		return level.on_ground() and not level.lan.is_in_deep_water() and level.feet().x >= Sluice.APPROACH.x


	func climb_rear_steps(level: ZhenxiSluiceSection, observe_landing := Callable()) -> bool:
		for landing: Rect2 in Sluice.REAR_STEPS:
			await walk_right(level, landing.position.x - 35.0, 130)
			Input.action_press(&"ui_right")
			Input.action_press(&"jump")
			await step(2)
			Input.action_release(&"jump")
			await walk_right(level, landing.position.x + 33.0, 65)
			await step(32)
			if not level.on_ground() or absf(level.feet().y - landing.position.y) >= 3.0:
				print("Rear landing missed at %s, expected %s" % [level.feet(), landing.position])
				return false
			if observe_landing.is_valid():
				await observe_landing.call(landing)
		return true


	func walk_right(level: ZhenxiSluiceSection, target_x: float, timeout: int) -> void:
		Input.action_press(&"ui_right")
		for frame in timeout:
			if level.feet().x >= target_x:
				break
			await step(1)
		Input.action_release(&"ui_right")


	func board_from_entry(level: ZhenxiSluiceSection) -> bool:
		Input.action_press(&"ui_right")
		for frame in 55:
			if level.feet().x >= 303.0:
				break
			await step(1)
		Input.action_press(&"jump")
		await step(2)
		Input.action_release(&"jump")
		for frame in 80:
			if level.standing_on_gate():
				break
			if level.feet().x >= level.gate.position.x + 106.0:
				Input.action_release(&"ui_right")
			await step(1)
		Input.action_release(&"ui_right")
		return level.standing_on_gate()


	func position_for_jump(level: ZhenxiSluiceSection, height: float, descending: bool) -> bool:
		Input.action_press(&"ui_right")
		for frame in 64:
			if level.gate.end.x - level.feet().x <= 23.0:
				break
			await step(1)
		Input.action_release(&"ui_right")
		for frame in ceili(Sluice.CYCLE * 60.0):
			var on_descent := level.age >= Sluice.UPPER_PAUSE and level.age < Sluice.LOWER_ARRIVAL
			var lined_up := on_descent and level.gate.position.y >= height if descending \
				else level.age > Sluice.ASCENT_START and level.gate.position.y <= height
			if lined_up:
				return level.standing_on_gate() and level.gate.end.x - level.feet().x < 55.0
			await step(1)
		return false


	func jump_right(frames: int) -> void:
		Input.action_press(&"ui_right")
		Input.action_press(&"jump")
		await step(2)
		Input.action_release(&"jump")
		await step(frames)
		Input.action_release(&"ui_right")


	func jump_to_catch(level: ZhenxiSluiceSection) -> bool:
		Input.action_press(&"ui_right")
		Input.action_press(&"jump")
		await step(2)
		Input.action_release(&"jump")
		for frame in 240:
			if level.on_catch_deck() or level.reached_exit:
				break
			await step(1)
		Input.action_release(&"ui_right")
		return level.on_catch_deck() and not level.reached_exit


	func recover_from_catch(level: ZhenxiSluiceSection) -> bool:
		for frame in 90:
			var gap := Sluice.GATE_STOP.x + Sluice.GATE_SIZE.x * 0.75 - level.feet().x
			if absf(gap) < 9.0:
				break
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
			Input.action_press(&"ui_right" if gap > 0.0 else &"ui_left")
			await step(1)
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		for frame in 150:
			if level.gate.position.is_equal_approx(Sluice.GATE_STOP):
				break
			await step(1)
		if not level.gate.position.is_equal_approx(Sluice.GATE_STOP):
			return false
		Input.action_press(&"jump")
		await step(2)
		Input.action_release(&"jump")
		for frame in 65:
			if level.standing_on_gate():
				return true
			await step(1)
		return false


	func step(count: int) -> void:
		for frame in count:
			await _tree.physics_frame
			await _tree.process_frame


func run() -> void:
	use_memory_progress()
	for service_name in ["BattleAssist", "QuestLog"]:
		var service := root.get_node_or_null(service_name)
		if service != null:
			for child in service.get_children():
				if child is CanvasLayer:
					child.hide()
	var level := Sluice.new()
	root.add_child(level)
	current_scene = level
	root.title = Sluice.TITLE
	print("ZHENXI_SLUICE_PLAYTEST_READY")
	if "--verify" in OS.get_cmdline_user_args():
		await verify(level)
		expect_save_untouched()
		finish("ZHENXI SLUICE")


func verify(level: ZhenxiSluiceSection) -> void:
	var controls := RouteInput.new(self)
	await controls.step(10)
	check(level.lan.is_in_deep_water(), "Lan starts in the submerged side passage")
	await capture("00_a18_water", level)
	var surfaced := await controls.leave_pool(level, func(): await capture("00_bank_join", level))
	check(surfaced, "Swimming up and jumping from the surface reaches the real shore")
	if not surfaced:
		level.reset(Sluice.APPROACH)
	await capture("01_front_of_well", level)
	check(level.shadow_wall.rear_view == 0.0 and not level.shadow_wall.shadow_on_cloth,
		"From the dry approach the decoys cast a row of shadows without Lan")
	check(await controls.board_from_entry(level), "A real jump boards the gate from the approach")
	if not level.standing_on_gate():
		return
	var before := level.lan.position
	await controls.step(75)
	check(level.standing_on_gate() and level.lan.position.x > before.x + 10.0 and level.lan.position.y > before.y + 10.0,
		"The gate carries Lan along both axes with the controls released")
	check(await controls.position_for_jump(level, 490.0, true), "The throat lines up while Lan is still on the descending gate")
	check(level.shadow_wall.shadow_on_cloth, "Lan physically enters the light and her shadow reaches the same cloth")
	await capture("02_lan_in_the_shadows", level)
	await controls.jump_right(115)
	check(level.reached_exit, "One ordinary jump from the moving gate reaches the exit")
	await capture("03_throat", level)
	check(not level.reached_comic_threshold and level.shadow_wall.rear_view < 1.0,
		"Clearing the sluice leaves the rear of the cloth beyond the climb")
	var observe_landing := func(landing: Rect2): await capture("04_step_%d" % int(landing.position.y), level)
	check(await controls.climb_rear_steps(level, observe_landing), "Lan climbs the three maintenance landings using ordinary jumps")
	check(level.shadow_wall.rear_view == 1.0 and not level.shadow_wall.shadow_on_cloth,
		"The rear landing reveals the physical rods and armor at the same installation")
	await capture("04_behind_the_cloth", level)
	await controls.walk_right(level, Sluice.COMIC_THRESHOLD + 8.0, 130)
	check(level.reached_comic_threshold, "The rear landing reaches the onward comic cut")
	await capture("05_onward_cut", level)

	level.reset(Sluice.APPROACH)
	Input.action_press(&"ui_right")
	await controls.step(650)
	Input.action_release(&"ui_right")
	check(not level.reached_exit, "Holding right for a full gate cycle cannot reach the exit")
	check(level.on_catch_deck() and level.gate.position.is_equal_approx(Sluice.GATE_STOP),
		"The plate stays docked when Lan is on the catch deck and nobody boards")

	level.reset(Sluice.APPROACH)
	check(await controls.board_from_entry(level) and await controls.position_for_jump(level, 340.0, true),
		"Lan can deliberately jump before the opening lines up")
	var health := level.lan.combat_stats.health
	var caught_early := await controls.jump_to_catch(level)
	var catch_frame := Engine.get_physics_frames()
	check(caught_early and level.lan.combat_stats.health == health,
		"An early jump drops onto the catch deck without taking damage")
	await capture("06_catch_deck", level)
	var recovered := await controls.recover_from_catch(level)
	var reboard_seconds := float(Engine.get_physics_frames() - catch_frame) / Engine.physics_ticks_per_second
	check(recovered and reboard_seconds <= 2.5, "Lan reboards with an ordinary jump in %.2f seconds" % reboard_seconds)
	if not recovered:
		return
	check(await controls.position_for_jump(level, 537.0, false), "The opening is reachable on the first upward trip")
	await controls.jump_right(115)
	check(level.reached_exit, "An ordinary jump from the returning plate reaches the exit")

	level.reset(Sluice.APPROACH)
	check(await controls.board_from_entry(level) and await controls.position_for_jump(level, 640.0, true),
		"Lan can also ride below the opening before jumping")
	check(await controls.jump_to_catch(level), "A jump below the opening lands on the catch deck")
	catch_frame = Engine.get_physics_frames()
	recovered = await controls.recover_from_catch(level)
	reboard_seconds = float(Engine.get_physics_frames() - catch_frame) / Engine.physics_ticks_per_second
	check(recovered and reboard_seconds <= 2.5,
		"A late miss also allows reboarding in %.2f seconds" % reboard_seconds)

	# Isolate the catch-side wall with Lan already east of the dock.
	level.reset(Vector2(Sluice.GATE_STOP.x + Sluice.GATE_SIZE.x + 78.0, Sluice.LOWER_DECK.position.y))
	Input.action_press(&"ui_right")
	var wall_jump_seen := false
	for frame in 450:
		if frame % 5 == 0 and (level.on_catch_deck() or level.lan.air_state == LanPlayer.AirState.WALL_SLIDING):
			Input.action_press(&"jump")
		if frame % 5 == 2:
			Input.action_release(&"jump")
		await controls.step(1)
		wall_jump_seen = wall_jump_seen or level.lan.animated_sprite.animation == &"wall_jump"
		if level.reached_exit:
			break
	Input.action_release(&"jump")
	Input.action_release(&"ui_right")
	check(wall_jump_seen and not level.reached_exit, "Repeated wall jumps under the overhang stay below the exit")
	level.reset()
	await controls.step(10)
	check(level.lan.is_in_deep_water() and not level.reached_comic_threshold and not level.catch_requested,
		"Reset restores the submerged entrance and clears the passage state")


func capture(name: String, level: ZhenxiSluiceSection) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	if is_instance_valid(level):
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))

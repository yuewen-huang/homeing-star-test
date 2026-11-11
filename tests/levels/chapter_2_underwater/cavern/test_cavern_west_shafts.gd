extends "test_sunken_cavern_graybox.gd"


func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	player.reset_after_map_fall(level.marker("w60"))
	await step(3)
	await capture("a19_shaft_bottom")
	var kicks: Array[float] = []
	var started := await walk_plain(level.vector(nav_points.route_3_0))
	var reached := started and await wall_jump_ascent(level.vector(nav_points.route_3_1), kicks)
	check(reached and kicks.has(-1.0) and kicks.has(1.0),
		"A19 climbs into A4 with real alternating wall jumps (directions=%s)" % [kicks])
	if reached:
		check(await drop_to(Vector2(3424.0, level.marker("w60").y)),
			"A4's original opening still drops to the A19 bank")

	var shaft: Node2D = level.west_shaft
	var bottom: Vector2 = level.marker("dry_base")
	var upper: Vector2 = level.marker("dry_turn")
	var health := player.combat_stats.health
	var fires: Array[float] = []
	shaft.pad.fired.connect(func() -> void: fires.append(shaft.clock))
	shaft.clock = 0.0
	player.reset_after_map_fall(bottom)
	await step(3)
	await capture("a22_spring_and_extended_spears")
	check(shaft.blades.size() == 5 and await step_onto_west_spring(),
		"A22 has five bars and the pad is reached by ordinary walking")
	var low_peak := player.position.y
	var hops := 0
	for i in 230:
		var launching := player.velocity.y < -410.0
		await step(1)
		low_peak = minf(low_peak, player.position.y)
		if not launching and player.velocity.y < -410.0: hops += 1
	var hop_height: float = shaft.pad.position.y - low_peak
	check(hops >= 2 and fires.is_empty() and hop_height >= 95.0 and hop_height <= 125.0
		and player.combat_stats.health == health,
		"Standing over the pad repeats low bounces without launching (height=%.1f)" % hop_height)
	var early_peak := await fire_outside_window(shaft.OPEN_AT - 0.88)
	check(fires.size() == 1 and early_peak > 4420.0 and early_peak < low_peak
		and player.combat_stats.health == health - shaft.SPEAR_DAMAGE,
		"An early stomp hits the underside of an extended spear and loses health (peak=%.1f)" % early_peak)
	await check_air_recovery()
	health = player.combat_stats.health
	player.reset_after_map_fall(bottom)
	await step(3)
	check(await step_onto_west_spring(), "Lan can retry after hitting a spear")
	var late_peak := await fire_outside_window(shaft.OPEN_AT + 0.04)
	check(fires.size() == 2 and late_peak > 3996.0 and late_peak < 4420.0
		and player.combat_stats.health == health - shaft.SPEAR_DAMAGE,
		"A late stomp passes the lower spear and takes damage from the upper one (peak=%.1f)" % late_peak)

	health = player.combat_stats.health
	player.reset_after_map_fall(bottom)
	await step(3)
	shaft.clock = shaft.OPEN_AT - 1.10
	var used_spring := await spring_ascent(upper)
	check(used_spring and fires.size() == 3 and player.combat_stats.health == health,
		"One timed stomp clears the shaft and lands on the street unharmed")
	if used_spring:
		await capture("a22_timed_stomp_exit")
		var at_lip := await walk_plain(Vector2(2442.0, upper.y))
		shaft.clock = shaft.OPEN_AT - 1.28
		check(at_lip and await descend_west_shaft(bottom) and player.combat_stats.health == health,
			"A22's timed descent reaches the crypt unharmed")

	shaft.clock = 0.0
	player.reset_after_map_fall(bottom)
	await step(3)
	check(await step_onto_west_spring(), "The downslash route starts on an ordinary pad bounce")
	var bounced := 0
	for blade in shaft.blades:
		var approach_x: float = blade.end_x + blade.side * 23.0
		if not await downslash_spear(Vector2(blade.tip_x, blade.y), approach_x, bounced < 2): break
		bounced += 1
	check(bounced == shaft.blades.size() and player.combat_stats.health == health,
		"A22 chains five alternating downslash rebounds unharmed (%d landed)" % bounced)
	if bounced == shaft.blades.size():
		for i in 145:
			if standing() and absf(player.position.y - upper.y) < 4.0: break
			await step(1)
		check(standing() and absf(player.position.y - upper.y) < 4.0 and fires.size() == 3,
			"The last downslash reaches the street without a high-speed spring launch")
		await capture("a22_downslash_exit")
	await check_spear_contacts()
	await end_test()


func check_air_recovery() -> void:
	var shaft: Node2D = level.west_shaft
	check(player.hit_reaction_active and player.velocity.y > 0.0,
		"The spear initially interrupts the spring and sends Lan downward")
	player.double_jump_used = true
	player.aerial_dash_used = true
	Input.action_press(&"ui_left")
	var elapsed := 0
	for i in 24:
		if not player.hit_reaction_active: break
		await step(1)
		elapsed += 1
	check(elapsed in range(9, 16) and not player.hit_reaction_active and not standing()
		and player.velocity.y > 0.0 and player.double_jump_used and player.aerial_dash_used,
		"Air control returns during the same fall without restoring spent air actions (%d frames)" % elapsed)
	var x := player.position.x
	await step(8)
	check(player.position.x < x - 6.0 and not standing(), "Real direction input steers before landing")
	Input.action_press(&"ui_down")
	await step(1)
	release()
	check(player.attack_state == LanPlayer.AttackState.FAST_FALL and player.position.y < shaft.pad.position.y - 100.0,
		"A fresh downslash input works in midair after spear recovery")


func check_spear_contacts() -> void:
	var shaft: Node2D = level.west_shaft
	var blade: Variant = shaft.blades[0]
	var health := player.combat_stats.health
	var near_tip := Vector2(blade.end_x - 9.0, blade.y + 17.0)
	shaft.clock = shaft.OPEN_AT
	player.reset_after_map_fall(near_tip)
	await step(10)
	check(player.combat_stats.health == health, "A fully retracted spear has no lingering hitbox")

	shaft.clock = shaft.OPEN_UNTIL - 0.02
	player.reset_after_map_fall(near_tip)
	for i in 20:
		if player.combat_stats.health < health: break
		await step(1)
	check(player.combat_stats.health == health - shaft.SPEAR_DAMAGE,
		"The extending spearhead damages Lan on its first side contact")
	for i in 16:
		if not player.hit_reaction_active: break
		await step(1)
	check(not player.hit_reaction_active and player.air_state == LanPlayer.AirState.RISING and player.velocity.y < 0.0,
		"Side impact hands control back on the rising part of the same recoil")

	await step(90)
	health = player.combat_stats.health
	shaft.clock = 0.0
	player.reset_after_map_fall(Vector2(blade.wall_x + blade.side * 34.0, blade.y - 110.0))
	for i in 55:
		if player.combat_stats.health < health: break
		await step(1)
	check(player.combat_stats.health == health - shaft.SPEAR_DAMAGE,
		"An ordinary landing on the spear shaft deals contact damage")
	var largest_drop := 0.0
	for i in 37:
		var previous_y := player.position.y
		await step(1)
		largest_drop = maxf(largest_drop, player.position.y - previous_y)
	check(largest_drop < 24.0 and player.combat_stats.health == health - shaft.SPEAR_DAMAGE,
		"Spear recoil stays continuous and the same touch cannot drain health per frame (max step %.1f)" % largest_drop)


func fire_outside_window(phase: float) -> float:
	for i in 130:
		if player.position.y < level.west_shaft.pad.position.y - 60.0 and player.fast_fall.can_start(player):
			break
		await step(1)
	level.west_shaft.clock = phase
	var health := player.combat_stats.health
	Input.action_press(&"ui_down")
	await step(1)
	Input.action_release(&"ui_down")
	var peak := player.position.y
	for i in 125:
		await step(1)
		peak = minf(peak, player.position.y)
		if player.combat_stats.health < health: break
	return peak


func downslash_spear(at: Vector2, approach_x: float, needs_double: bool) -> bool:
	var used_double := false
	var slashing := false
	var highest := player.position.y
	var nearest := INF
	for i in 150:
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		var aim := at.x if player.position.y < at.y - 2.0 else approach_x
		var dx := aim - player.position.x
		if absf(dx) > 6.0:
			Input.action_press(&"ui_right" if dx > 0.0 else &"ui_left")
		if needs_double and not used_double and player.position.y < at.y + 85.0 \
				and player.velocity.y >= -30.0 and player.can_start_double_jump():
			Input.action_press(&"jump")
			used_double = true
		if player.position.y < at.y - 9.0: nearest = minf(nearest, absf(at.x - player.position.x))
		if not slashing and absf(at.x - player.position.x) < 24.0 and player.position.y < at.y - 9.0:
			Input.action_press(&"ui_down")
			slashing = true
		await step(1)
		highest = minf(highest, player.position.y)
		Input.action_release(&"jump")
		Input.action_release(&"ui_down")
		if slashing and player.fast_fall.last_contacts == 1 and player.velocity.y < -500.0:
			release()
			return true
		if slashing and standing(): break
	release()
	print("Missed spear at ", at, " from ", player.position, " high=", highest, " x gap=", nearest)
	return false

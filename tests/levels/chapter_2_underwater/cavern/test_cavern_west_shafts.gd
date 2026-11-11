extends "test_cavern_a22_timing.gd"


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

	observe_shaft()
	await play_return("timed")
	var bottom: Vector2 = level.marker("dry_base")
	var health := player.combat_stats.health
	check(await descend_west_shaft(bottom) and player.combat_stats.health == health,
		"A22's timed descent reaches the crypt unharmed")
	await check_spear_contacts()
	await end_test()


func check_spear_contacts() -> void:
	var shaft: Node2D = level.west_shaft
	var blade: Variant = shaft.blades[1]
	var health := player.combat_stats.health
	var near_tip := Vector2(blade.end_x - 9.0, blade.y + 17.0)
	shaft.clock = shaft.OPEN_AT
	player.reset_after_map_fall(near_tip)
	await step(10)
	check(player.combat_stats.health == health, "The cleared space beyond a retracted spear has no lingering hitbox")

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

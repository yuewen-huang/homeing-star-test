extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var boss: MasterBoss = room.get_node("MasterBoss")
	var player: LanPlayer = room.get_node("Lan")
	boss.set_process(false)
	player.set_physics_process(false)
	var spacing = boss.get_node("BodySpacing")
	spacing.set_physics_process(false)
	boss.position = Vector2(0, 555)
	boss.state = MasterBoss.State.CHASE
	var gap: float = spacing.gap_for(player)
	var health := player.combat_stats.health
	for direction: float in [-1.0, 1.0]:
		player.reset_after_map_fall(Vector2(direction * 180.0, 555))
		await physics_frame
		for tick in 120:
			player.velocity = Vector2(-direction * 270.0, 0)
			player.move_on_action_clock()
		check((player.global_position.x - boss.global_position.x) * direction >= gap - 0.01, "Walking into either side stops at body clearance without crossing")
		player.attack_state = LanPlayer.AttackState.ATTACK_2X
		check(spacing.limit_motion(player, Vector2(-direction * 500, 0)).x == 0, "Ordinary attack advance cannot walk through the torso")
		player.attack_state = LanPlayer.AttackState.NONE
		check(is_equal_approx(spacing.limit_motion(player, Vector2(direction * 10, 0)).x, direction * 10), "Walking away is never sticky")
		for skill in [LanPlayer.AttackState.DODGE_ATTACK_1X, LanPlayer.AttackState.DODGE_ATTACK_3X, LanPlayer.AttackState.INSTANT_DASH, LanPlayer.AttackState.AERIAL_DASH, LanPlayer.AttackState.SPECIAL_ATTACK]:
			player.attack_state = skill
			check(spacing.limit_motion(player, Vector2(-direction * 500, 0)).x == -direction * 500, "Existing crossing skill retains movement")
		player.attack_state = LanPlayer.AttackState.NONE
		player.start_back_dodge(-direction)
		check(spacing.limit_motion(player, Vector2(-direction * 500, 0)).x == -direction * 500, "Dodge can cross the boss")
		player.reset_after_map_fall(Vector2(-direction * 10, 555))
		for tick in 60: spacing.settle(player, 1.0 / 60.0)
		check(player.global_position.x * direction < 0 and absf(player.global_position.x) >= gap - 0.01, "After crossing, separation keeps the new side")
		player.air_state = LanPlayer.AirState.RISING
		check(spacing.limit_motion(player, Vector2(direction * 500, 0)).x == direction * 500, "Jumping over keeps free horizontal motion")
	player.reset_after_map_fall(Vector2(10, 555))
	var before := player.global_position
	spacing.settle(player, 1.0 / 60.0)
	check(player.global_position.distance_to(before) <= 3.01, "Existing overlap resolves softly without a snap")
	boss.parry_pause_remaining = 1.0
	before = player.global_position
	spacing.settle(player, 0.1)
	check(player.global_position == before, "Hit-stop freezes soft correction")
	boss.parry_pause_remaining = 0.0
	for direction: float in [-1.0, 1.0]:
		var edge := player.world_min_x if direction < 0 else player.world_max_x
		boss.position.x = edge - direction * 20
		player.reset_after_map_fall(Vector2(edge, 555))
		for tick in 60: spacing.settle(player, 1.0 / 60.0)
		check(is_equal_approx(player.position.x, edge) and absf(player.global_position.x - boss.global_position.x) >= gap - 0.01, "At arena edges the idle master yields; Lan never enters the wall")
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 240)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	room.add_child(wall)
	wall.position = Vector2(100, 450)
	boss.position = Vector2(20, 555)
	player.reset_after_map_fall(Vector2(75, 555))
	await physics_frame
	for tick in 60: spacing.settle(player, 1.0 / 60.0)
	check(player.position.x < 90 and absf(player.global_position.x - boss.global_position.x) >= gap - 0.01, "Real terrain collision blocks correction; master yields without pushing Lan through it")
	wall.queue_free()
	await physics_frame
	boss.position = Vector2(0, 555)
	player.reset_after_map_fall(Vector2(gap, 555))
	boss.start_food_mechanism()
	boss.food_mechanism.begin_collect()
	for tick in 10: spacing.settle(player, 1.0 / 60.0)
	var food := boss.food_mechanism
	food.selected = food.wanted
	food.bag[food.wanted] = 1
	check(food.submit(food.wanted), "Body clearance still permits food delivery")
	boss._cancel_food_mechanism()
	check(player.combat_stats.health == health, "Body overlap and separation never deal contact damage")
	boss.phase = 2
	boss.state = MasterBoss.State.PHASE_2_IDLE
	check(spacing.limit_motion(player, Vector2(-500, 0)).x == 0.0, "Second-form grounded body also preserves spacing")
	boss.state = MasterBoss.State.TRANSFORM
	check(spacing.limit_motion(player, Vector2(-500, 0)).x == -500, "Transformation does not pull the player around")
	boss.manual_control = true
	check(spacing.limit_motion(player, Vector2(-500, 0)).x == -500, "Manual development observers remain unconstrained")
	room.free()
	current_scene = null
	check(get_nodes_in_group(&"combat_body_spacing").is_empty(), "Leaving the encounter removes its movement constraint")
	expect_save_untouched()
	finish("MASTER BODY SPACING")

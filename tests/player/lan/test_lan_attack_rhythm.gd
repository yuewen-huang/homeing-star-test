extends "../../support/harness.gd"
## A queued combo must yield to a defensive input at the recovery boundary.

func run() -> void:
	use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.position = Vector2(600, 520)
	player.fallback_ground_y = 520
	player.world_min_x = 0
	player.world_max_x = 1280
	world.add_child(player)
	for defense in ["jump", "dash", "dodge", "parry"]:
		player.reset_after_map_fall(Vector2(600, 520))
		player.combat_stats.stamina = player.combat_stats.max_stamina
		for frame in 4: await physics_frame
		player.start_attack_1x(1.0)
		for frame in 90:
			if player.can_cancel_normal_attack_recovery() or player.attack_state == LanPlayer.AttackState.NONE:
				break
			await physics_frame
		var can_cancel := player.can_cancel_normal_attack_recovery()
		check(can_cancel, "An active normal attack reaches interruptible recovery")
		if not can_cancel: break
		player.update_combat_input_buffers(0.0, true, defense == "dodge", defense == "parry")
		if defense == "jump": Input.action_press(&"jump")
		if defense == "dash": Input.action_press(&"instant_dash")
		for frame in 2: await physics_frame
		var ok := false
		match defense:
			"jump": ok = player.velocity.y < 0 and player.attack_state == LanPlayer.AttackState.NONE
			"dash": ok = player.attack_state == LanPlayer.AttackState.INSTANT_DASH
			"dodge": ok = player.ground_action_state == LanPlayer.GroundActionState.BACK_DODGE
			"parry": ok = player.defense_state != LanPlayer.DefenseState.NONE
		check(ok and not player.attack_queued, "%s wins over a combo queued on the same frame" % defense)
		Input.action_release(&"jump")
		Input.action_release(&"instant_dash")
	check(player.get_node("StateTrace").report_count == 0, "Recovered action never leaves inconsistent animation ownership")
	expect_save_untouched()
	world.queue_free()
	await wait_frames(2)
	finish("LAN ATTACK RECOVERY")

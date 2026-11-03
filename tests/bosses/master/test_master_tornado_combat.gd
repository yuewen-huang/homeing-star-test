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
	boss.get_node("BodySpacing").set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	boss.position = Vector2(0, 555)
	for facing: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			player.reset_after_map_fall(Vector2(0, 555))
			var original := CombatAttackData.new(&"uppercut", boss, 10, 10, 0, 0)
			var wind := MasterTornado.new()
			boss.add_child(wind)
			wind.top_level = true
			wind.global_transform = Transform2D(0, Vector2(facing, 1), 0, boss.global_position)
			wind.setup(boss, original, {player.get_instance_id(): true})
			wind.effect.advance(.8)
			var h := -wind.to_local(player.hurtbox.get_node("CollisionShape2D").global_position).y
			var center := .8 * MasterTornado.SPEED + h * .38
			player.global_position = wind.to_global(Vector2(center + side * 45, 0))
			wind._update_pull()
			var pull := player.horizontal_combat_wind()
			check(pull * facing * side < 0 and absf(pull) <= 105.0, "Both facings and both sides pull inward below ordinary walking speed")
			check(not player.is_jump_blocked() and not player.is_combat_anchored(), "Suction never anchors or blocks jumping")
			var before := player.global_position.x
			for tick in 90:
				await physics_frame
				wind._update_pull()
				player.velocity = Vector2(facing * side * LanPlayer.WALK_SPEED + player.horizontal_combat_wind(), 0)
				player.move_on_action_clock()
			print("ESCAPE facing=", facing, " side=", side, " before=", before, " after=", player.global_position.x, " force=", player.horizontal_combat_wind(), " scale=", player.evaded_action_clock.scale())
			check((player.global_position.x - before) * facing * side > 100 and is_zero_approx(player.horizontal_combat_wind()), "Ordinary outward walking escapes even a stationary worst-case pull field")
			player.reset_after_map_fall(wind.to_global(Vector2(center + side * 45, 0)))
			wind._update_pull()
			boss.parry_pause_remaining = .2
			check(is_zero_approx(player.horizontal_combat_wind()), "Hit-stop also freezes cached suction")
			boss.parry_pause_remaining = 0
			player.start_back_dodge(facing * side)
			wind._update_pull()
			check(is_zero_approx(player.horizontal_combat_wind()), "Dodge remains free of suction")
			player.reset_after_map_fall(wind.to_global(Vector2(center, 0)))
			player.combat_stats.restore_health()
			var health := player.combat_stats.health
			wind._resolve(.8, .8)
			check(player.combat_stats.health < health and wind.hit_targets.has(player.get_instance_id()), "Previously struck uppercut target still takes independent wind damage")
			var after := player.combat_stats.health
			wind._resolve(.8, .82)
			wind._update_pull()
			check(player.combat_stats.health == after and is_zero_approx(player.horizontal_combat_wind()), "A wind hits once and stops pulling after settlement")
			wind.cancel()
			check(not player.combat_winds.has(wind.get_instance_id()), "Cancellation removes the field immediately")
			await process_frame
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER TORNADO COMBAT")

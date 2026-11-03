extends "../../support/harness.gd"
func finish_exchange(boss: MasterBoss) -> void:
	boss.start_phase_1_action(&"vertical")
	boss.phase_1_action.advance(boss.phase_1_action.timeline.duration + 0.01)
	boss._update_recovery(boss.recovery_remaining + 0.01)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	room.set_combat_simulation(true)
	var boss: MasterBoss = room.adapter.master
	var player: LanPlayer = room.player
	boss.set_process(false)
	player.set_physics_process(false)
	player.global_position = boss.global_position + Vector2(-1500, 0)
	boss.phase_1_ai.clock = 1.0
	var calm := MasterPhase1AI.new()
	var drunk := MasterPhase1AI.new()
	for i in 4: drunk.drank()
	var timeline := boss.action_library.move(&"combo_three")
	check(drunk.remaining_opening(&"combo_three", timeline) < calm.remaining_opening(&"combo_three", timeline), "Four drinks tighten the extra recovery without speeding up the authored attacks")
	var total := boss.combat_stats.max_health + 123
	boss.combat_stats.apply_health_damage(total)
	check(boss.phase == 1 and boss.combat_stats.health == ceili(boss.combat_stats.max_health * .8), "A lethal burst stops at the first drink gate instead of skipping phase one")
	check(boss.combat_stats.max_health - boss.combat_stats.health + boss.combat_stats.deferred_damage == total, "Every point of burst damage is retained")
	for layer in range(1, 5):
		boss._update_chase(.01, 0)
		check(boss.state == MasterBoss.State.DRINK and boss.charged_power == layer - 1, "Drink %d starts only at the safe decision point" % layer)
		boss._interrupt_for_special(.5)
		check(boss.state == MasterBoss.State.DRINK, "Break attacks cannot restart an already committed drink")
		boss._finish_drink()
		check(boss.charged_power == layer and boss.phase == 1, "Only the completed drink grants layer %d" % layer)
		boss._finish_drink()
		check(boss.charged_power == layer, "Duplicate animation completion cannot grant another layer")
		check(boss.phase_1_ai.exchanges_since_drink == 0 and not boss.phase_1_ai.drink_due(layer), "No consecutive drinks without a combat exchange")
		boss._update_recovery(boss.recovery_remaining + .01)
		if layer == 2:
			boss._update_chase(.01, 0)
			var food := boss.food_mechanism
			check(food != null and boss.phase == 1, "Burst damage cannot skip the two-layer food mechanism")
			food.begin_collect()
			boss.combat_stats.apply_health_damage(1000)
			check(boss.food_mechanism == food and boss.phase == 1, "Damage during collection remains banked without cancelling the mechanism")
			player.global_position = boss.global_position
			for round_index in food.rounds:
				food.selected = food.wanted
				food.bag[food.wanted] = 1
				food.submit(food.wanted)
			food.advance(food.opening_time + .01)
			food.advance(2.0)
			check(boss.food_mechanism == null, "Original success opening and full getup finish normally")
			player.global_position = boss.global_position + Vector2(-1500, 0)
		if layer < 4:
			finish_exchange(boss)
			check(boss.phase_1_ai.drink_due(layer), "A completed exchange releases the next queued drink without waiting twenty seconds")
	check(boss.dodge_response_ready and boss.combat_stats.health == 1 and boss.combat_stats.deferred_damage > 0, "Fourth layer gives the original finger flick an opportunity even after lethal burst")
	finish_exchange(boss)
	boss._update_chase(.01, 0)
	check(boss.phase == 1, "One final exchange cannot immediately erase the fourth layer")
	boss._cancel_phase_1_action()
	finish_exchange(boss)
	boss._update_chase(.01, 0)
	check(boss.phase == 2 and boss.combat_stats.health == boss.combat_stats.max_health and boss.combat_stats.deferred_damage == 0, "Ranged-only play can finish two exchanges and settle banked damage into the original phase handoff")
	boss.combat_stats.apply_health_damage(7)
	check(boss.combat_stats.health == boss.combat_stats.max_health - 7, "Phase two has ordinary damage without gates")
	room.reset_room()
	boss = room.adapter.master
	check(boss.charged_power == 0 and boss.combat_stats.deferred_damage == 0, "Retry clears all progression and retained damage")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER DRINK PROGRESSION")

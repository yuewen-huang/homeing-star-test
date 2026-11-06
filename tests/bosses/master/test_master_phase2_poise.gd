extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var boss: MasterBoss = room.get_node("MasterBoss")
	boss.set_process(false)
	boss.manual_control = true
	boss._enter_phase_2()
	boss._enter_phase_2_idle(0)
	var attack := CombatAttackData.new(&"test_claw", boss, 10, 3, 0, 0)
	for round_index in 4:
		for beat in 3:
			boss.state = MasterBoss.State.PHASE_2_BODY_ACTION
			boss.on_attack_parried(attack, boss.global_position)
		boss._enter_phase_2_idle(1.5)
		var hp := boss.combat_stats.health
		boss.receive_attack_hit(AttackHitContext.new(&"test_punish", 10, 9999), boss.position - Vector2(100,0))
		check(boss.combat_stats.health == hp-10, "Punish hit retains ordinary health damage")
		check(not boss.poise_broken and not boss.can_offer_break_empower(), "Repeated defended rounds cannot grant default weakness")
	check(not boss.has_poise_bar(), "Second form has no poise bar")
	current_scene = null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("MASTER PHASE TWO NO DEFAULT BREAK")

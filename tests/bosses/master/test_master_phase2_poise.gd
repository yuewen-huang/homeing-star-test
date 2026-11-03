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
	boss.charged_power = 1
	var maximum := boss.combat_stats.max_poise
	boss.combat_stats.apply_poise_damage(50)
	for state in [MasterBoss.State.PHASE_2_ATTACK, MasterBoss.State.PHASE_2_BODY_ACTION, MasterBoss.State.PHASE_2_HOWL]:
		boss.state = state
		boss._update_poise_refill(10)
		check(boss.combat_stats.poise == maximum - 50, "Attacks and howl cannot erase posture earned by defense")
	boss._enter_phase_2_idle(100)
	boss._update_poise_refill(5.9)
	check(boss.combat_stats.poise == maximum - 50, "Five seconds of repositioning preserves posture progress")
	boss._update_poise_refill(1.1)
	check(boss.combat_stats.poise == maximum - 46, "Only time beyond six seconds regenerates at four per second")
	boss.receive_attack_hit(AttackHitContext.new(&"test_normal", 10, CombatTuning.LAN_NORMAL_ATTACK_POISE), boss.position - Vector2(100,0))
	var after_hit := boss.combat_stats.poise
	boss._update_poise_refill(5)
	check(boss.combat_stats.poise == after_hit, "A real normal hit restarts the grace period")
	boss.combat_stats.restore_poise()
	boss.poise_seen = maximum
	var attack := CombatAttackData.new(&"test_claw", boss, 10, 3, 0, 0)
	var parries := 0
	for round_index in 3:
		for beat in 3:
			boss.state = MasterBoss.State.PHASE_2_BODY_ACTION
			boss.on_attack_parried(attack, boss.global_position)
			parries += 1
			boss._update_poise_refill(.6)
			if boss.poise_broken: break
		if boss.poise_broken: break
		boss._enter_phase_2_idle(1.5)
		for hit in 2:
			boss.receive_attack_hit(AttackHitContext.new(&"test_punish", 10, CombatTuning.LAN_NORMAL_ATTACK_POISE), boss.position - Vector2(100,0))
		boss._update_poise_refill(1.5)
		boss.state = MasterBoss.State.PHASE_2_HOWL
		boss._update_poise_refill(3)
	check(boss.poise_broken and parries <= 9, "Three defended rounds plus normal punish hits produce a break")
	check(boss.break_empower_available, "Earned break enables the existing empower reward")
	boss._update_poise_refill(CombatTuning.BOSS_BREAK_WINDOW_DURATION)
	check(not boss.poise_broken and boss.combat_stats.poise == maximum, "Break still ends and fully restores posture after five seconds")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER PHASE TWO POISE")

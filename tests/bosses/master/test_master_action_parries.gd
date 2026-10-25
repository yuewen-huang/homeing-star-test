extends "../../support/harness.gd"
var master: MasterBoss
var lan: LanPlayer
var results: Array[int] = []

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	master.attack_hitbox.hit_resolved.connect(func(_target: Node, result: CombatHitResult.Type) -> void: results.append(result))
	for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL, BattleAssistSettingsService.Difficulty.HARD]:
		assist.set_difficulty(difficulty)
		results.clear()
		master.position = Vector2(0, 555)
		master.movement_direction = 1
		master.combat_stats.restore_poise()
		lan.reset_after_map_fall(Vector2(master.ATTACK_APPROACH_DISTANCE, 555))
		lan.combat_stats.restore_health()
		lan.parry_chain.cancel()
		await physics_frame
		master.start_phase_1_action(&"combo_three")
		lan.start_parry(true)
		lan.animated_sprite.pause()
		var ticks := 0
		var released := false
		while master.phase_1_action != null and ticks < 1200:
			lan.combat_clock += 1.0 / 120.0
			master._process(1.0 / 120.0)
			if not released and not results.is_empty():
				check(results[0] == CombatHitResult.Type.PARRY_SUCCESS, "Real first blade contact reaches Lan's parry route")
				check(master.parry_pause_remaining > 0.0, "Settled parry pauses the new action")
				lan.finish_defense()
				released = true
			ticks += 1
		check(ticks < 1200 and results.size() == 3, "Three physical contacts settle exactly once each")
		if difficulty == BattleAssistSettingsService.Difficulty.NORMAL:
			check(results == [CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.PARRY_SUCCESS], "Normal difficulty assists only the remaining cuts of this combo")
			check(lan.combat_stats.health == lan.combat_stats.max_health, "Assisted combo parries lose no health")
			check(master.combat_stats.poise == master.combat_stats.max_poise - 3 * CombatTuning.BOSS_NORMAL_PARRY_POISE, "Shared poise tuning settles once per parried contact")
		else:
			check(results == [CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.NORMAL_HIT, CombatHitResult.Type.NORMAL_HIT], "Hard difficulty requires another manual parry for each later cut")
			check(lan.combat_stats.health < lan.combat_stats.max_health, "Unparried hard-mode cuts deal production damage")
		master.start_phase_1_action(&"combo_three")
		check(not lan.parry_chain.covers(master, lan.combat_clock), "Previous assistance cannot carry into a replay")
		master._interrupt_for_special(0)
		await process_frame
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER ACTION PARRIES")

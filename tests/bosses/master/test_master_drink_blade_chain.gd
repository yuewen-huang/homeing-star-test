extends "../../support/harness.gd"
## Real tutorial actors and hurtbox settlement: pressure beats cannot seed the
## blade group; any manual blade parry seeds the remaining contacts on normal.
var master: MasterBoss
var lan: LanPlayer

func tick_to(at: float) -> void:
	while master.drink_blade.elapsed + 0.000001 < at:
		master._process(minf(1.0 / 120.0, at - master.drink_blade.elapsed))

func contact() -> CombatHitResult.Type:
	var attack := master.attack_hitbox.attack
	var result: CombatHitResult.Type = lan.get_node("Hurtbox").receive_attack(attack)
	master.attack_hitbox._complete_hit(lan, lan.global_position, attack, result)
	return result

func finish_feedback() -> void:
	# Lan's physics clock also releases hit-stop; advancing only Sprite2D frames
	# would leave her frozen in the previous red-parry invulnerability pose.
	for frame in 60:
		lan._physics_process(1.0 / 60.0)
		await process_frame

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	lan.set_physics_process(false)
	for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL, BattleAssistSettingsService.Difficulty.HARD, BattleAssistSettingsService.Difficulty.NIGHTMARE]:
		assist.set_difficulty(difficulty)
		for manual in [-1, 3, 4, 5]:
			master._cancel_press_return()
			master.phase = 1
			master.charged_power = 4
			master.drink_blade_used = false
			master.combat_stats.restore_health()
			lan.reset_after_map_fall(Vector2(180, 555))
			lan.combat_stats.restore_health()
			lan.parry_chain.cancel()
			master._start_drink()
			tick_to(5.86)
			lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
			check(contact() == CombatHitResult.Type.PARRY_SUCCESS, "The last pressure beat can be manually parried")
			var pressure_key := master.get_parry_chain_key()
			await finish_feedback()
			var edge_key: StringName = &""
			var ids: Array[StringName] = []
			var expected_health := lan.combat_stats.max_health
			for index in range(3, 6):
				tick_to(float(MasterDrinkBlade.WAVES[index]) + 0.01)
				lan.combat_clock += 0.6
				if index == 3:
					edge_key = master.get_parry_chain_key()
					check(edge_key != pressure_key and not lan.parry_chain.covers(master, lan.combat_clock), "Pressure assistance cannot carry into the blade group")
				check(master.get_parry_chain_key() == edge_key, "All three blade contacts share one group")
				ids.append(master.attack_hitbox.attack.attack_id)
				if index == manual: lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
				var assisted: bool = difficulty == BattleAssistSettingsService.Difficulty.NORMAL and manual >= 3 and index > manual
				var expected := CombatHitResult.Type.PARRY_SUCCESS if index == manual or assisted else CombatHitResult.Type.NORMAL_HIT
				var result := contact()
				check(result == expected, "Difficulty %d, manual beat %d, blade beat %d settles correctly" % [difficulty, manual, index])
				if assisted:
					check(lan.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS, "Automatic red contacts use ordinary parry without PLUS")
				if expected == CombatHitResult.Type.NORMAL_HIT: expected_health -= MasterDrinkBlade.DAMAGE
				check(lan.combat_stats.health == expected_health, "Only unprotected blade contacts cost health")
				check(master.drink_blade != null, "Neither manual nor automatic parries interrupt the ultimate")
				await finish_feedback()
			check(ids[0] != ids[1] and ids[1] != ids[2], "Grouped assistance keeps separate damage identities")
	master._cancel_press_return()
	check(not lan.parry_chain.covers(master, lan.combat_clock), "The blade group expires with the ultimate")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER DRINK BLADE CHAIN")

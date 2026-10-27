extends "../../support/harness.gd"
var lan: LanPlayer
var boss: MasterBoss
var serial := 0

func fresh() -> void:
	lan.reset_after_map_fall(Vector2(115,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(100)
	boss.action_clock.clear()

func attack() -> CombatAttackData:
	serial += 1
	return CombatAttackData.new(StringName("dodge_test_%d" % serial),boss,24,12,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)

func seek_roll(seconds: float) -> void:
	lan.combat_timeline.seek(seconds * lan.BACK_DODGE_SPEED_SCALE,true)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	lan = room.get_node("Lan")
	boss = room.get_node("MasterBoss")
	lan.set_physics_process(false)
	boss.set_process(false)
	await process_frame
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	for time in [0.0,0.079,0.081,0.199,0.201,0.4]:
		fresh()
		lan.start_back_dodge(-1)
		seek_roll(time)
		check(lan.is_invulnerable() == (time < .2), "Roll protection boundary at %.3f seconds" % time)
		var hit := attack()
		var result := lan.receive_combat_hit(hit)
		check(result == (CombatHitResult.Type.EVADED if time < .2 else CombatHitResult.Type.NORMAL_HIT), "Actual gold settlement at %.3f seconds" % time)
		check((lan.dodge_bullet_time_remaining > 0) == (time <= .08), "Perfect reward boundary at %.3f seconds" % time)
		if time <= .08:
			check(is_equal_approx(lan.dodge_bullet_time_remaining,.35) and is_equal_approx(boss.get_action_time_scale(),.25), "Perfect dodge grants only .35 s / .25x reward")
		lan.start_dodge_attack_1x(1)
		check(not lan.is_invulnerable(), "Counterattack cannot carry general dodge invulnerability")
		check(lan.receive_combat_hit(attack()) == CombatHitResult.Type.NORMAL_HIT, "New attack can hit the counterattack even during slow motion")
	# A late first contact is not protected; an attack evaded during the roll stays settled.
	fresh()
	var announced := attack()
	announced.evasion_key = announced.attack_id
	lan.start_back_dodge(-1)
	seek_roll(.3)
	check(lan.receive_combat_hit(announced) == CombatHitResult.Type.NORMAL_HIT, "First contact after invulnerability ends deals damage")
	fresh()
	announced = attack()
	announced.evasion_key = announced.attack_id
	lan.start_back_dodge(-1)
	seek_roll(.1)
	check(lan.receive_combat_hit(announced) == CombatHitResult.Type.EVADED, "Contact during invulnerability is evaded")
	seek_roll(.3)
	check(lan.receive_combat_hit(announced) == CombatHitResult.Type.EVADED, "Already evaded group stays settled after invulnerability")
	check(lan.receive_combat_hit(attack()) == CombatHitResult.Type.NORMAL_HIT, "A different group can hit after invulnerability")
	fresh()
	var old_cast := attack()
	lan.start_back_dodge(-1)
	lan.receive_combat_hit(old_cast)
	lan.start_dodge_attack_1x(1)
	var next_cast := CombatAttackData.new(old_cast.attack_id,boss,24,12,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	check(lan.receive_combat_hit(next_cast)==CombatHitResult.Type.NORMAL_HIT,"Reused textual attack ID on a later cast is not immune")
	fresh()
	lan.start_parry_success(boss.global_position)
	check(lan.can_dodge_cancel_defense(), "Successful parry accepts dodge cancellation")
	lan.dodge_input_buffer_remaining = lan.COMBAT_INPUT_BUFFER
	lan.dodge_buffer_direction = -1
	lan._physics_process(0)
	check(lan.ground_action_state == LanPlayer.GroundActionState.BACK_DODGE and lan.defense_state == LanPlayer.DefenseState.NONE, "Buffered L actually cancels success into dodge")
	fresh()
	lan.combat_stats.stamina = 0
	lan.start_parry_success(boss.global_position)
	check(not lan.can_dodge_cancel_defense(), "Success cancel still respects stamina")
	expect_save_untouched()
	finish("DODGE WINDOW")

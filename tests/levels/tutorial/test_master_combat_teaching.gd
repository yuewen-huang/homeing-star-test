extends "../../support/harness.gd"

var room: Node2D
var master: MasterBoss
var player: LanPlayer
var teaching: Node

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss")
	player = room.get_node("Lan")
	teaching = room.get_node("MasterCombatTeaching")
	master.set_process(false)
	player.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	teaching.set_process(false)
	await process_frame
	master.position = Vector2(220, 555)
	player.position = Vector2(40, 555)
	check(teaching != null, "Formal fight owns contextual teaching")
	check(teaching.lesson_player != null, "Opening owns the video lesson player")
	teaching._process(0)
	await capture("teaching_opening")
	for id: StringName in MasterBoss.OPENING_LESSONS:
		check(master.choose_clash_rhythm() == id, "Opening demonstrates %s in order" % id)
		master.start_clash_rhythm(id)
	check(master.opening_lessons_started == 3, "Opening progresses when an attack actually starts")
	check(CombatLessonCatalog.text(&"parry_chain", true).contains("普通难度"), "Normal video dialogue explains automatic follow-up parries")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(not assist.uses_parry_chain_assist(), "Hard lesson uses manual parries")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	check(not assist.uses_parry_chain_assist(), "Nightmare uses manual parries")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)

	master.start_clash_rhythm(&"spin_delayed")
	teaching._process(0)
	check(CombatLessonCatalog.text(&"master_heavy_chain").contains("五刀"), "Heavy chain explains the fixed five-cut pattern")
	await capture("teaching_red")
	master.start_clash_rhythm(&"air_plunge")
	teaching._process(0)
	check(CombatLessonCatalog.text(&"master_air_chain").contains("三道剑气"), "Air chain explains the ordinary parry sequence")
	await capture("teaching_gold")
	master._interrupt_for_special(0)
	master.state = MasterBoss.State.CHASE
	master.combat_stats.restore_poise()
	var health := master.combat_stats.health
	var attack := master._create_attack_data(&"lesson", 0, Vector2.ZERO, CombatAttackData.DangerType.NORMAL)
	var parries_to_break := ceili(float(master.combat_stats.max_poise) / CombatTuning.BOSS_NORMAL_PARRY_POISE)
	for i in parries_to_break:
		master.on_attack_parried(attack, master.global_position)
	check(master.poise_broken and master.combat_stats.poise == 0, "Settled parries break poise using the shared tuning")
	check(master.combat_stats.health == health, "Parries reward poise pressure without health damage")
	check(teaching.parries == parries_to_break, "Teaching responds to shared settled parry events")
	teaching._process(0)
	check(CombatLessonCatalog.actions(&"poise_throw") == [&"interact"] and CombatLessonCatalog.text(&"poise_throw").contains("面向"), "Broken poise video teaches the real throw and facing requirement")
	await capture("teaching_break")
	master._update_poise_refill(CombatTuning.BOSS_STAGGER_DURATION - 0.1)
	check(master.poise_broken, "Throw opportunity remains open during the shared stagger window")
	master._update_poise_refill(0.2)
	check(not master.poise_broken, "Shared stagger duration ends the throw opportunity")

	master.combat_stats.restore_health()
	master.combat_stats.restore_poise()
	master.receive_hit(1, player.global_position)
	check(master.combat_stats.health == master.combat_stats.max_health - CombatTuning.MASTER_PLAYER_HIT_HEALTH and master.combat_stats.poise == master.combat_stats.max_poise - CombatTuning.MASTER_PLAYER_HIT_POISE, "Legacy sword contact reads shared master tuning")
	for charge: float in [0.0, 0.5, 1.0]:
		master.combat_stats.restore_health()
		master.combat_stats.restore_poise()
		player.special_attack_cooldown_remaining = 0.0
		player.perform_special_attack(1.0, charge)
		var effect: Node = player.active_attack_effects.back()
		var hit := effect.skill_hit_context as SkillHitContext
		master.receive_skill_hit(hit, player.global_position)
		check(master.combat_stats.health == master.combat_stats.max_health - roundi(lerpf(CombatTuning.LAN_SPECIAL_DAMAGE, CombatTuning.LAN_SPECIAL_CHARGED_DAMAGE, charge)), "I charge %.1f settles health damage" % charge)
		check(master.combat_stats.poise == master.combat_stats.max_poise - roundi(lerpf(CombatTuning.LAN_SPECIAL_POISE_DAMAGE, CombatTuning.LAN_SPECIAL_CHARGED_POISE_DAMAGE, charge)), "I charge %.1f also scales poise damage" % charge)
		player.cancel_uncommitted_attack_effects()
	check(player.ultimate_hit_context.damage == CombatTuning.LAN_ULTIMATE_HIT_DAMAGE, "Ultimate uses shared tuning")
	check(LanPlayer.SPECIAL_ATTACK_MAX_DAMAGE == CombatTuning.LAN_SPECIAL_MAX_DAMAGE, "Throw rewards breaking poise")
	for danger in [CombatAttackData.DangerType.NORMAL, CombatAttackData.DangerType.COUNTERABLE_DANGER, CombatAttackData.DangerType.UNPARRYABLE_DANGER]:
		var expected: int = CombatTuning.boss_player_damage(danger)
		check(master._create_attack_data(&"balance", 0, Vector2.ZERO, danger).health_damage == expected, "Phase one danger %d uses tuned damage" % danger)
	master._enter_phase_2()
	for danger in [CombatAttackData.DangerType.NORMAL, CombatAttackData.DangerType.COUNTERABLE_DANGER, CombatAttackData.DangerType.UNPARRYABLE_DANGER]:
		check(master.attack_health_damage(danger) == CombatTuning.boss_player_damage(danger), "Phase two danger %d uses tuned damage" % danger)
	master.combat_stats.restore_health()
	player.cancel_uncommitted_attack_effects()
	player.position = Vector2(40, 555)
	player.start_ultimate_combo()
	var steps := 0
	while player.ultimate_active and steps < 100:
		player.update_ultimate_combo(1.0)
		steps += 1
	var ultimate_damage := master.combat_stats.max_health - master.combat_stats.health
	var expected_ultimate := LanPlayer.ULTIMATE_TRAVERSAL_COUNT * CombatTuning.LAN_ULTIMATE_HIT_DAMAGE + LanPlayer.ULTIMATE_FINISH_SLASH_COUNT * CombatTuning.LAN_ULTIMATE_FINISHER_HIT_DAMAGE
	check(not player.ultimate_active and ultimate_damage == expected_ultimate, "Real ultimate traversals and replays settle shared damage (%d total)" % ultimate_damage)
	check(master.combat_stats.poise == 100, "Ultimate preserves its separate health-only settlement")
	player.combat_stats.apply_health_damage(player.combat_stats.health)
	teaching._process(0)
	check(not teaching.key_hint.visible, "Defeat hides overhead combat teaching")
	expect_save_untouched()
	finish("MASTER COMBAT TEACHING")

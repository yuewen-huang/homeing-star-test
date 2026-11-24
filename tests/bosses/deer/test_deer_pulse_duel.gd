extends "../../support/harness.gd"
## The encounter owns energy/flasks, while each new deer form owns its health and wounds.
var room: Chapter1DeerBossRoom

func run() -> void:
	var save := use_memory_progress()
	save.locked.append(SaveProgressService.ABILITY_HEAL)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene = packed
	root.add_child(room)
	current_scene = room
	await wait_frames(4)
	var lan := room.player
	var duel := lan.pulse_duel
	check(duel != null and lan.heal.charges == 2 and not lan.is_ability_locked(SaveProgressService.ABILITY_HEAL),
		"Formal battle lends two usable flasks even before the permanent heal unlock")
	var heal_slot: Control = lan.get_node("SkillBar").slot_nodes[&"heal"]
	check(heal_slot.visible, "Borrowed flasks appear on the existing heal slot")
	for phase in range(1, 5):
		room.encounter._spawn_phase(phase, 1420)
		var boss := room.deer
		boss.set_physics_process(false)
		boss.invulnerable = false
		lan.reset_after_map_fall(Vector2(1320, 555))
		check(duel == lan.pulse_duel and duel.boss == boss and boss.pulse_duel == duel, "Form %d binds the same duel" % phase)
		check(boss.combat_stats.max_health == [350, 500, 800, 550][phase-1], "Form %d uses its declared health budget" % phase)
		check(duel.boss_internal_hp == 0 and not boss.boss_counter_enabled(), "Fresh wound segment and retired counter")
		await check_action(duel, boss, lan)
		if phase == 1:
			lan.combat_stats.set_health_ratio(0.1)
			check(lan.heal.try_cast() and lan.heal.charges == 1 and lan.combat_stats.health == 60, "First flask heals 50")
			duel.player_energy = 19
		if phase == 2: check(lan.heal.charges == 1, "Flask use survives actor replacement")
	room.restart_mist_phase()
	check(lan.pulse_duel != duel and lan.pulse_duel.player_energy == 0 and lan.heal.charges == 2, "A retry starts a new economy")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).end_boss_attempt(room.encounter)
	await wait_frames(2)
	check(lan.is_ability_locked(SaveProgressService.ABILITY_HEAL) and not heal_slot.visible,
		"Leaving the fight restores the original heal unlock and HUD")
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER SHARED PULSE")

func check_action(duel: LanPlayer.PulseDuel, boss: DeerDuelBoss, lan: LanPlayer) -> void:
	var initial := duel.player_energy
	if boss.phase == 2: check(initial == 19, "Earned energy survives the handoff")
	var hp := boss.combat_stats.health
	var normal := CombatAttackData.new(&"blade", boss, 10, 0, 0, 0)
	lan.parry_resolved.emit(normal, false)
	lan.parry_resolved.emit(normal, false)
	lan.parry_resolved.emit(CombatAttackData.new(&"fast", boss, 10, 0, 0, 0), false)
	check(duel.player_energy == initial + 14 and duel.boss_internal_hp == 15, "Fast contacts respect both cooldowns")
	var finisher := CombatAttackData.new(&"last", boss, 10, 0, 0, 0)
	finisher.combo_finisher = true
	lan.parry_resolved.emit(finisher, true)
	check(duel.player_energy == initial + 14, "Assisted parry grants no energy")
	lan.parry_resolved.emit(finisher, false)
	check(duel.player_energy == initial + 39 and duel.boss_internal_hp == 50 and boss.combat_stats.health == hp, "Manual finisher bypasses cooldown without direct damage")
	for i in 3:
		lan.parry_resolved.emit(CombatAttackData.new(&"red", boss,18,0,0,0,CombatAttackData.DangerType.COUNTERABLE_DANGER),false)
	check(duel.player_energy == 100 and duel.boss_internal_hp == 100, "Both stores cap at 100")
	lan.position.x = 830
	check(lan.get_ready_throw_target() == null, "Range gates E")
	lan.position.x = 1320
	Input.action_press(&"interact")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact")
	check(boss.is_throw_controlled() and boss.combat_stats.health == hp and duel.player_energy == 0, "E reserves energy and delays damage to the blast")
	for i in 118: await physics_frame
	check(boss.combat_stats.health == hp - 140 and not boss.is_throw_controlled(), "One burst settles 40 plus 100 and releases control")

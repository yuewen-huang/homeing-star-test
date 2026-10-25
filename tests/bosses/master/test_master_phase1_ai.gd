extends "../../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var brain := MasterPhase1AI.new()
	brain.rng.seed = 173
	check(brain.choose(0) == &"horizontal", "Opening begins with the familiar horizontal slash")
	brain.started(&"horizontal")
	check(brain.choose(0) == &"vertical", "Second opening teaches the delayed vertical slash")
	brain.started(&"vertical")
	for layer in 5:
		var seen: Dictionary = {}
		var valid := true
		for i in 250:
			brain.clock += 2.0
			var pick := brain.choose(layer)
			valid = valid and int(brain.UNLOCKS[pick]) <= layer and pick != brain.last_move
			valid = valid and float(brain.ready_at.get(pick, -INF)) <= brain.clock
			seen[pick] = true
			brain.started(pick)
		check(valid and seen.size() == brain.available(layer).size(), "Layer %d uses its full table, respects cooldowns and avoids immediate repeats" % layer)
	check(not brain.available(3).has(&"rise_unbalance") and brain.available(4).has(&"rise_unbalance"), "Loss of balance only unlocks when fully drunk")
	check(not brain.available(4).has(&"finger_flick") and not brain.available(4).has(&"peanut_sword") and not brain.available(4).has(&"dodge"), "Both excluded mechanisms and the dodge never enter AI selection")
	brain = MasterPhase1AI.new()
	brain.advance(1, 0.81, 0, false)
	check(not brain.drink_due(0), "No drink before the first blood threshold")
	brain.advance(0.01, 0.19, 0, false)
	check(brain.drink_entitlements == 4 and brain.drink_due(0), "Burst damage queues all four blood thresholds without skipping drinks")
	brain.drank()
	brain.advance(19.99, 1.0, 0, false)
	check(not brain.drink_due(1) and brain.drink_entitlements == 4, "Healing does not duplicate triggers; the 20-second spacing is real")
	brain.advance(0.02, 1.0, 0, false)
	check(brain.drink_due(1) and not brain.drink_due(4), "Queued next drink becomes eligible, four layers remain capped")
	brain.advance(4.1, 1.0, 800, true)
	check(brain.pursuing() and brain.choose(0) == &"combo_three", "Sustained evasion selects the existing three-cut pursuit")
	brain.started(&"combo_three")
	check(not brain.pursuing(), "Catching the player resets pursuit pressure")
	brain.advance(3, 1.0, 800, true)
	brain.advance(0.1, 1.0, 240, true)
	check(is_zero_approx(brain.chase_time), "Briefly re-engaging resets an untriggered evasion timer")
	brain.advance(3, 1.0, 800, true)
	brain.advance(0.1, 1.0, 240, true)
	check(is_zero_approx(brain.chase_time), "Briefly re-engaging resets an untriggered evasion timer")
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var master := room.get_node("MasterBoss") as MasterBoss
	# Isolate the regular table here; the full food encounter has its own suite.
	master.flying_sword_enabled = false
	var player := room.get_node("Lan") as LanPlayer
	master.set_process(false)
	player.set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	master.attack_hitbox.set_physics_process(false)
	master.position = Vector2(0, 555)
	player.position = Vector2(200, 555)
	await physics_frame
	for i in 60:
		master._process(1.0 / 60.0)
		if master.phase_1_action != null: break
	check(master.phase_1_action != null and master.phase_1_action.id == &"horizontal", "Production AI autonomously starts the real opening action")
	var serial := master.attack_serial
	var ticks := 0
	while master.phase_1_action != null and ticks < 1000:
		master._process(1.0 / 120.0)
		ticks += 1
	check(ticks < 1000 and master.state == MasterBoss.State.RECOVER, "Production attack completes through the shared action clock")
	master._process(0.01)
	check(master.attack_serial == serial, "Recovery cannot restart a second action in the same frame")
	master._interrupt_for_special(1.0)
	master.combat_stats.set_health_ratio(0.79)
	master._process(0.5)
	check(master.state == MasterBoss.State.RECOVER and master.charged_power == 0, "Blood threshold cannot steal a promised punish opening")
	master._process(0.51)
	master._process(0.01)
	check(master.state == MasterBoss.State.DRINK and master.charged_power == 0, "Drink begins after recovery; layers do not unlock before it finishes")
	master._on_body_animation_finished()
	check(master.charged_power == 1 and master.phase == 1, "Finished gulp unlocks precisely one table tier")
	var last := master.phase_1_ai.last_drink
	master.combat_stats.set_health_ratio(0.19)
	master.recovery_remaining = 0
	master._process(0.01)
	master._process(0.01)
	check(master.state != MasterBoss.State.DRINK and master.charged_power == 1, "Newly crossed blood thresholds cannot chain immediate drinks")
	master._cancel_phase_1_action()
	for layer in range(2, 5):
		master.state = MasterBoss.State.CHASE
		master.phase_1_ai.advance(20.1, 0.19, 0, false)
		master._process(0.01)
		check(master.state == MasterBoss.State.DRINK, "Eligible queued drink %d starts without replaying prior blood triggers" % layer)
		master._on_body_animation_finished()
		check(master.charged_power == layer and master.phase_1_ai.last_drink - last >= 20, "Drink %d respects spacing and settles once" % layer)
		last = master.phase_1_ai.last_drink
	check(master.phase == 1 and master.charged_power == 4, "Fourth drink leaves the fully drunk move table playable")
	master.state = MasterBoss.State.CHASE
	master._on_poise_depleted()
	master._process(0.01)
	check(master.phase_1_action == null, "Broken poise prevents autonomous attacks")
	master.poise_broken = false
	master.position.x = 0
	player.position.x = 800
	master.phase_1_ai.chase_time = 4.1
	master.play_walk()
	master._process(0.25)
	check(master.position.x > 90 and master.position.x < 200, "Anti-evasion pursuit walks quickly without teleporting")
	master.manual_control = true
	master.state = MasterBoss.State.CHASE
	master.position.x = 0
	player.position.x = 200
	for i in 120: master._process(1.0 / 60.0)
	check(master.phase_1_action == null and master.position.x == 0, "Manual preview never runs autonomous AI")
	master.start_phase_1_action(&"combo_three")
	master.combat_stats.apply_health_damage(master.combat_stats.health)
	check(master.phase == 2 and master.phase_1_action == null and master.combat_stats.health == master.combat_stats.max_health, "Health defeat cancels phase one and preserves the real phase-two handoff")
	room.free()
	current_scene = null
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.set_combat_simulation(true)
	check(dev.combat_simulation and not dev.adapter.master.manual_control and dev.adapter.master.combat_target == dev.player, "Development room opt-in uses the real phase-one AI and Lan")
	dev.reset_room()
	check(dev.combat_simulation and dev.adapter.master.charged_power == 0 and dev.adapter.master.phase_1_ai.drink_entitlements == 0, "Retry clears spirit, pending blood thresholds and AI history")
	dev.set_combat_simulation(false)
	check(dev.adapter.master.manual_control and dev.player.is_invulnerable(), "Leaving combat restores safe preview")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER PHASE ONE AI")

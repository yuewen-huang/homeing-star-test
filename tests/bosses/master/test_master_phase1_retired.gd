extends "../../support/harness.gd"
## Production room must keep non-attacking actions and phase two after the retirement.

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var master := room.get_node("MasterBoss") as MasterBoss
	var lan := room.get_node("Lan") as LanPlayer
	master.set_process(false)
	lan.set_physics_process(false)
	await process_frame
	check(not master.has_node("CombatTimeline"), "Retired attack timeline is absent from production scene")
	for action: StringName in MasterPhase1Art.FRAMES.get_animation_names():
		check(String(action).get_slice("_", 0) in ["idle", "walk", "drink", "hurt"], "Only non-attacking phase-one animation remains: " + action)
	for action: StringName in [&"idle", &"walk_start", &"walk", &"drink", &"hurt"]:
		check(MasterPhase1Art.FRAMES.has_animation(action) and MasterPhase1Art.FRAMES.get_frame_count(action) > 0, "Retained body artwork loads: " + action)
	master.position.x = 500
	lan.position.x = -500
	master._process(0.9)
	check(master.animated_sprite.animation == &"walk_start", "Production AI can begin walking")
	master._on_body_animation_finished()
	var before := master.position.x
	master._process(0.1)
	check(master.animated_sprite.animation == &"walk" and master.position.x < before, "Production walk still moves toward Lan")
	master.position.x = lan.position.x + 150
	master.manual_control = true
	master.play_idle()
	for tick in 1200: master._process(1.0 / 60.0)
	check(master.phase == 1 and master.state == MasterBoss.State.CHASE and master.attack_hitbox.attack == null, "Manual preview never starts an autonomous attack at melee range")
	check(master.animated_sprite.animation == &"idle" and not master.wind_effect.visible, "Close-range idle has no old attack effects")
	var teaching := room.get_node("MasterCombatTeaching")
	check(teaching._pending.is_empty(), "No retired opening attack video is queued")
	for layer in range(1, MasterBoss.CHARGED_POWER_MAX + 1):
		master._start_drink()
		check(master.attack_hitbox.attack == null and master.animated_sprite.animation == &"drink", "Drink remains harmless, including former ultimate layer")
		master._on_body_animation_finished()
		check(master.charged_power == layer, "Completed drink retains its spirit layer")
	check(master.phase == 1 and master.charged_power == 4, "Four drinks do not replace the health-based phase boundary")
	master.combat_stats.apply_health_damage(master.combat_stats.health)
	check(master.phase == 2 and master.state == MasterBoss.State.TRANSFORM, "Health depletion retains second-form transformation")
	master._on_body_animation_finished()
	for action: StringName in [&"phase_2_attack_1", &"phase_2_attack_2", &"phase_2_uppercut", &"phase_2_dash", &"phase_2_special_attack"]:
		master._enter_phase_2_idle(0)
		master._start_phase_2_attack(action)
		master.animated_sprite.pause()
		var active := false
		for frame in master.animated_sprite.sprite_frames.get_frame_count(action):
			master.animated_sprite.frame = frame
			if master.attack_hitbox.attack != null: active = true
		check(active and master.wind_effect.sprite_frames.has_animation(action), "Second-form attack still has artwork and active collision: " + action)
		master._finish_phase_2_attack()
		check(master.attack_hitbox.attack == null, "Second-form attack releases collision")
	room.free()
	current_scene = null
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	check(dev.adapter.combo_names().size() == 3, "Developer room separates non-attacking art, phase two and newly imported actions")
	check(not dev.adapter.supports_combat_simulation() and not dev.adapter.has_ultimate_preview(), "Retired phase-one combat entries are unavailable")
	for index in MasterPhase1Art.ACTIONS.size():
		dev.play_action(index)
		check(dev.adapter.master.animated_sprite.animation == MasterPhase1Art.ACTIONS[index] and dev.adapter.master.attack_hitbox.attack == null, "Developer room previews only non-attacking phase-one actions")
	dev.select_combo(1)
	check(dev.adapter.supports_combat_simulation(), "Second-form combat simulation remains available")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER PHASE ONE RETIREMENT")

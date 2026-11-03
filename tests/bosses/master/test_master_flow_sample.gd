extends "../../support/harness.gd"

const SAMPLE := preload("res://scripts/dev/master_flow_sample.gd")
var hit_times: Array[float] = []
var results: Array[int] = []

func run() -> void:
	use_memory_progress()
	var original := MasterActionLibrary.new()
	var baseline: String = JSON.stringify(original.data.moves)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var master: MasterBoss = room.get_node("MasterBoss")
	var lan: LanPlayer = room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	SAMPLE.install(master)
	master.phase_1_ai = SAMPLE.new()
	var timeline := master.action_library.move(&"combo_three")
	check(timeline.errors.is_empty() and timeline.warnings.is_empty(), "Sample uses valid measured swords and all declared swing frames")
	master.start_phase_1_action(&"combo_three")
	var geometry_unchanged := true
	for cut: Dictionary in timeline.cuts:
		var heavy := master.phase_1_action._make_ribbon(cut)
		var plain_cut := cut.duplicate(true)
		plain_cut.blade_weight = 0.0
		var plain := master.phase_1_action._make_ribbon(plain_cut)
		for frame in 33:
			var at := float(cut.swing) * frame / 32.0
			geometry_unchanged = geometry_unchanged and heavy.blade_pose(at) == plain.blade_pose(at)
		heavy.free()
		plain.free()
	check(geometry_unchanged, "Heavy dressing leaves all sampled collision geometry identical")
	master.phase_1_action.advance(0.50)
	var rendered_blade: MasterBladeTrail = master.phase_1_action._ribbons[0]
	check(rendered_blade.shader_material.shader == MasterPhase1Palette.BRUSH and rendered_blade.weight == 0.0,
		"Rejected ring material is disabled; original brush is restored")
	for step in 2:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		master.phase_1_action.advance(0.09)
	master._interrupt_for_special(0)
	check(JSON.stringify(MasterActionLibrary.new().data.moves) == baseline, "Sample does not modify other specimens or production data")
	master.attack_hitbox.hit_resolved.connect(func(_target: Node, result: CombatHitResult.Type) -> void:
		results.append(result)
		if master.phase_1_action != null: hit_times.append(master.phase_1_action.elapsed))
	for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL, BattleAssistSettingsService.Difficulty.HARD]:
		assist.set_difficulty(difficulty)
		for placement in [Vector2(-1, 132), Vector2(1, 132), Vector2(-1, 200), Vector2(1, 200)]:
			var direction: float = placement.x
			var gap: float = placement.y
			master.position = Vector2(0, 555)
			master.movement_direction = direction
			master.combat_stats.restore_poise()
			lan.reset_after_map_fall(Vector2(direction * gap, 555))
			lan.combat_stats.restore_health()
			lan.parry_chain.cancel()
			hit_times.clear()
			results.clear()
			await physics_frame
			master.start_phase_1_action(&"combo_three")
			var action := master.phase_1_action
			master.parry_pause_remaining = 0.1
			master._process(0.02)
			check(is_zero_approx(action.elapsed) and master.position.x == 0.0, "Hit-stop freezes entry step as well as body and blade")
			master.parry_pause_remaining = 0.0
			lan.start_parry(true)
			lan.animated_sprite.pause()
			var released := false
			var ticks := 0
			var recovery_safe := true
			var max_step := 0.0
			while master.phase_1_action != null and ticks < 1000:
				lan.combat_clock += 1.0 / 120.0
				var before := master.position.x
				master._process(1.0 / 120.0)
				max_step = maxf(max_step, absf(master.position.x - before))
				if not released and not results.is_empty():
					lan.finish_defense()
					released = true
				if action.elapsed >= timeline.cancel_at and master.attack_hitbox.attack != null: recovery_safe = false
				ticks += 1
			check(ticks < 1000 and results.size() == 3, "Three live blade contacts complete in either facing")
			print("SAMPLE contacts: ", hit_times, " results: ", results)
			for i in range(1, hit_times.size()):
				check(hit_times[i] - hit_times[i - 1] >= 0.35, "Actual contacts retain a readable manual-parry gap")
			if difficulty == BattleAssistSettingsService.Difficulty.NORMAL:
				check(results == [CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.PARRY_SUCCESS], "Normal assists this three-cut exchange")
			else:
				check(results == [CombatHitResult.Type.PARRY_SUCCESS, CombatHitResult.Type.NORMAL_HIT, CombatHitResult.Type.NORMAL_HIT], "Hard still requires a manual answer to each cut")
			check(recovery_safe and max_step < 4.0 and absf(master.position.x) <= gap - 100.0 + 0.01, "Recovery is harmless and entry preserves the initial target spacing")
			check(master.recovery_remaining >= 0.34, "Full drawn recovery is followed by the remaining punish window")
			await process_frame
	master.position = Vector2(master.world_max_x - 5.0, 555)
	master.movement_direction = 1.0
	master.start_phase_1_action(&"combo_three")
	master.phase_1_action.advance(0.36)
	check(master.position.x <= master.world_max_x, "Entry step respects arena boundary")
	master._interrupt_for_special(0)
	check(master.phase_1_action == null and master.attack_hitbox.attack == null, "Interruption clears the sample and its blade")
	room.free()
	current_scene = null
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(3)
	dev.play_action(0)
	check(dev.adapter.master.phase_1_action != null and dev.adapter.supports_combat_simulation(), "Sample has manual playback and an opt-in real combat entry")
	check(not dev.adapter.master.phase_1_action.timeline.data.cuts[0].has("blade_weight"), "Preview uses original blade light")
	dev.reset_room()
	await process_frame
	check(dev.specimen.get_child_count() == 2, "Reset clears sample effects")
	dev.set_combat_simulation(true)
	var specimen: MasterBoss = dev.adapter.master
	specimen.set_process(false)
	dev.player.set_physics_process(false)
	dev.player.position = specimen.position + Vector2(-200, 0)
	for i in 90:
		specimen._process(1.0 / 120.0)
		if specimen.phase_1_action != null: break
	check(specimen.phase_1_action != null and specimen.phase_1_action.id == &"combo_three", "Opt-in live AI starts the sample through the production executor")
	check(specimen.phase_1_ai is SAMPLE and not specimen.phase_1_ai.drink_due(0), "Sample isolates this exchange from drink progression")
	dev.set_combat_simulation(false)
	dev.select_combo(2)
	check(JSON.stringify(dev.adapter.master.action_library.data.moves) == baseline, "Leaving sample restores the unchanged production moves")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FLOW SAMPLE")

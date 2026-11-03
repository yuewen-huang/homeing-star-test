extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(4)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var player: LanPlayer = room.player
	player.set_physics_process(false)
	var output := "D:/HomingStar/homeing-star-test/artifacts/master-danger-lessons"
	DirAccess.make_dir_recursive_absolute(output)
	for index: int in [1, 3]:
		room.play_action(index)
		var boss: MasterBoss = room.adapter.master
		boss.set_process(false)
		var action := boss.phase_1_action
		var last := action.timeline.cuts.size() - 1
		var hit := action._attack_for_cut(last)
		var gold := index == 3
		check(hit.danger_type == (CombatAttackData.DangerType.UNPARRYABLE_DANGER if gold else CombatAttackData.DangerType.COUNTERABLE_DANGER), "Final contact has its actual danger type")
		check(action._attack_for_cut(0).danger_type == CombatAttackData.DangerType.NORMAL, "Earlier contact stays ordinary")
		var release: float = action.timeline.cuts[last].release
		action.advance(release - 0.10)
		check(boss.danger_flash.visible and boss.danger_flash_kind == (&"gold" if gold else &"red"), "Danger peak is visible before the committed release")
		for i in 2:
			await process_frame
			if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png(output.path_join("gold.png" if gold else "red.png"))
		player.reset_after_map_fall(boss.global_position + Vector2(-130, 0))
		player.combat_stats.restore_health()
		player.combat_simulation = true
		player.set_map_combat_mode(LanPlayer.MapCombatMode.DEFAULT)
		player.start_parry(true)
		var result := player.receive_combat_hit(hit)
		print("DANGER gold=", gold, " result=", result, " defense=", player.defense_state)
		check(result == CombatHitResult.Type.NORMAL_HIT if gold else result == CombatHitResult.Type.PARRY_SUCCESS, "Gold rejects parry; red enters real counter success")
		if not gold: check(player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "Red teaches the existing counter route")
		player.finish_defense()
		if gold:
			player.reset_after_map_fall(boss.global_position + Vector2(-130, 0))
			player.start_back_dodge(-1.0)
			check(player.receive_combat_hit(hit) == CombatHitResult.Type.EVADED, "Gold can be evaded through the existing dodge")
			action.advance(0.30)
			check(action.sword_qi != null and action.sword_qi.attack.danger_type == hit.danger_type, "Gold landing and travelling wave share one danger contract")
		boss._cancel_phase_1_action()
		check(not boss.danger_flash.visible, "Interrupt clears the danger cue")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER DANGER LESSONS")

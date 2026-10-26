extends "../support/harness.gd"
func run() -> void:
	var original_progress:=use_memory_progress()
	var original_ultimate:=original_progress.has_completed(SaveProgressService.STORY_MASTER_ULTIMATE_LEARNED)
	var room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	room.select_boss(1)
	room.select_combo(1)
	room.set_combat_simulation(true)
	var master: MasterBoss=room.adapter.boss
	master.set_process(false)
	room.player.set_physics_process(false)
	var player: LanPlayer=room.player
	var maximum:=player.combat_stats.max_health
	var normal:=CombatAttackData.new(&"practice_hit",master,10,0,100,0,CombatAttackData.DangerType.NORMAL)
	var lethal:=CombatAttackData.new(&"practice_lethal",master,maximum+10,0,100,0,CombatAttackData.DangerType.NORMAL)
	check(not player.is_invulnerable(),"Practice keeps actual damage and defense processing enabled")
	check(player.receive_combat_hit(normal)==CombatHitResult.Type.NORMAL_HIT,"Normal hit uses the production hit response")
	check(player.combat_stats.health==maximum-10,"Nonlethal damage remains visible on the real health bar")
	for i in 6:
		player.reset_after_map_fall(room.PLAYER_START)
		check(player.receive_combat_hit(lethal)==CombatHitResult.Type.NORMAL_HIT,"Lethal practice hit still resolves as a hit")
		check(player.combat_stats.health==maximum and player.hit_reaction_active,"Health refills without discarding the hit reaction")
		room._process(0)
	check(room._combat_result.is_empty() and not player.input_frozen,"Repeated lethal hits never freeze the practice session")
	check(master.is_processing()==false,"Health refill does not rebuild or restart the boss")
	player.reset_after_map_fall(room.PLAYER_START)
	player.defense_state=LanPlayer.DefenseState.PARRY_ACTIVE
	check(player.receive_combat_hit(lethal)==CombatHitResult.Type.PARRY_SUCCESS,"Real manual parries remain available")
	check(player.combat_stats.health==maximum,"Successful parry still prevents damage")
	player.reset_after_map_fall(room.PLAYER_START)
	master.phase_2_buff_remaining=master.PHASE_2_BUFF_DURATION
	master._start_phase_2_finale(100)
	var action:=master.phase_2_body_action
	action.advance(float(action.data.duration))
	var preview: SaveProgressService=room._preview_progress
	check(preview.has_completed(SaveProgressService.STORY_MASTER_ULTIMATE_LEARNED),"Real finale completion records its unlock in preview memory")
	check(preview._toast_label!=null and preview._toast_label.text.contains("必杀技已解锁"),"The actual finale unlock toast has initialized UI")
	check(original_progress.has_completed(SaveProgressService.STORY_MASTER_ULTIMATE_LEARNED)==original_ultimate,"Practice unlock leaves the original progress service untouched")
	room.set_combat_simulation(false)
	check(player.is_invulnerable(),"Leaving combat restores the safe observer mode")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEVELOPMENT COMBAT SURVIVAL")

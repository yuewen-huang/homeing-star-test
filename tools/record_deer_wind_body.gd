extends "../tests/bosses/deer/test_deer_wind_escape_readability.gd"
## Native recording of the shipped actor in the forest rematch room. Selects
## legal casts in a repeatable order and drives the ordinary player through input.

func record_opening() -> void:
	setup_route()
	deer.restart_duel()
	deer.position.x=1540
	lan.reset_after_map_fall(Vector2(1270,555))
	route_name="body_opening"
	var order := [2,3,4]
	var next := 0
	var rest := .35
	var pressed := {}
	var core_guarded := false
	var seen := {}
	var recorded_core := false
	for frame in 1200:
		release()
		deer.wait_left=999
		if deer.transform_left<=0 and deer.cast_index<0 and deer.opening<=0:
			rest-=1.0/60.0
			if next<order.size() and rest<=0 and deer.can_schedule_spell(order[next]):
				deer.start_spell(order[next])
				stamp("cast",{"spell":deer.SPELLS[order[next]]})
				next+=1
				rest=.26
		for spell in deer.spells:
			if not is_instance_valid(spell): continue
			if spell.kind=="meteors": visible_meteor_step(spell,true,pressed)
			if spell.kind=="phantom" and spell.age>=float(spell.spec.charge)-.07 and not pressed.has("phantom"):
				key(KEY_L,true)
				pressed["phantom"]=true
			if spell.kind=="core":
				if not core_guarded and spell.core_orb!=null and spell.core_orb.compression>=.25:
					key(KEY_K,true)
					core_guarded=true
				if spell.age>=3.4: recorded_core=true
		var clip: String=deer.human.clip
		if not seen.has(clip) and deer.human.source_frame>=5:
			seen[clip]=true
			await snap(clip)
		if (recorded_core or lan.combat_stats.health<=0): break
		await physics_frame
		wall+=1.0/60.0
	release()
	check(next==3 and recorded_core and seen.has_all(["change","hover","meteors","phantom","core"]),"Opening shows transform, drift, windfall, phantom and core on the production actor")
	room.encounter.stop()

func run() -> void:
	var save := use_memory_progress()
	node_added.connect(track_player_effect)
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	(root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested=true
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	await record_opening()
	var result := await acceptance_route(-80,.25,true,"I","normal",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("route.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	room.encounter.stop()
	current_scene=null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER WIND BODY RECORDING")

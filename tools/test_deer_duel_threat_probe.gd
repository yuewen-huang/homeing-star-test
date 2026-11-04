extends "../tests/support/harness.gd"
## Investigation only: records autonomous misses and lowland damage. No gameplay tuning.
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
var lan: LanPlayer
var trace: Array[Dictionary] = []

func on_move(id: StringName) -> void:
	trace.append({"move":String(id),"boss_x":deer.position.x,"player_x":lan.position.x,"gap":absf(deer.position.x-lan.position.x),"contacts":[],"first_active":{}})

func on_contact(_target: Node, result: int) -> void:
	if not trace.is_empty(): trace.back().contacts.append(result)

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("/deer_root_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer=room.adapter.boss
	lan=room.player
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	deer.terrain.advance(2.5)
	lan.reset_after_map_fall(Vector2(600,deer.ground_y_at(600)))
	deer.position=Vector2(820,deer.ground_y_at(820))
	deer.move_started.connect(on_move)
	deer.attack_hitbox.hit_resolved.connect(on_contact)
	for frame in 1200:
		await physics_frame
		if deer.attack_hitbox.attack==null or trace.is_empty() or not trace.back().first_active.is_empty(): continue
		var bounds := Rect2()
		var first := true
		for point: Vector2 in deer.geometry.points:
			var world_point := deer.to_global(point)
			if first: bounds=Rect2(world_point,Vector2.ZERO); first=false
			else: bounds=bounds.expand(world_point)
		trace.back().first_active={"boss_x":deer.position.x,"player_x":lan.position.x,"gap":absf(deer.position.x-lan.position.x),"path_bounds":str(bounds),"player_hurtbox":str(CombatHitQuery.hurtbox_rect(lan))}
	print("AUTONOMOUS_TRACE "+JSON.stringify(trace))
	# Isolate the actual root-wave resolver on its normal clock and real player hurtbox.
	# The deer is stopped solely to prevent mixing direct attack damage into this sample.
	deer.cancel_duel(false)
	deer.set_physics_process(false)
	deer.contest_wave.reset()
	lan.reset_after_map_fall(Vector2(-180,deer.ground_y_at(-180)))
	lan.combat_stats.restore_health()
	for frame in 2160:
		deer.contest_wave.advance(1.0/60)
		await physics_frame
	var lowland := {"simulation_seconds":36,"boss_attacks_disabled":true,"player_input":"none","start_x":-180,"end_x":lan.position.x,"end_hp":lan.combat_stats.health,"cycles":deer.contest_wave.cycle}
	print("LOWLAND "+JSON.stringify(lowland))
	var file:=FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("threat_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"autonomous_trace":trace,"lowland":lowland},"\t"))
	file.close()
	expect_save_untouched()
	finish("DEER THREAT INVESTIGATION - MEASUREMENTS ONLY")

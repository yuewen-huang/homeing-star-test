extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
var lan: LanPlayer
var result := -1
var impact_x := 0.0
var samples: Array[Dictionary] = []

func key(code: int, down: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func reset_pair(at: float, side: float) -> void:
	for code in [KEY_K,KEY_L]: key(code,false)
	deer.cancel_duel(false)
	deer.set_physics_process(false)
	deer.root_exercise=0 # Isolate authored skill push from independent terrain damage.
	deer.position=Vector2(at-side*220,415)
	deer._ground_body()
	deer.manual_control=false
	lan.reset_after_map_fall(Vector2(at,415))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	lan.set_input_frozen(false)
	lan.facing_direction=-side
	result=-1
	impact_x=at

func trial(index: int, at: float, side: float, defense: String = "hit") -> Dictionary:
	reset_pair(at,side)
	for f in 15: await physics_frame
	deer.start_move(index,at)
	if index==3:
		deer.pressure.release_leaf()
		deer.move=&""
		deer.wait_left=999
	deer.set_physics_process(true)
	var after_hit:=0
	for f in 200:
		key(KEY_K,false)
		key(KEY_L,false)
		if defense=="early" and f==8: key(KEY_K,true)
		if defense=="parry" and f==32: key(KEY_K,true)
		if defense=="dodge" and f==32: key(KEY_L,true)
		await physics_frame
		if result>=0:
			deer.set_physics_process(false)
			deer.close_attack()
			after_hit+=1
			if index==0 and side>0 and at>1000 and after_hit in [8,20]: await capture("rush_edge_%02d" % after_hit)
			if after_hit>=85: break
	for code in [KEY_K,KEY_L]: key(code,false)
	var row:={"move":String(DeerDuelBoss.MOVES[index]),"side":side,"defense":defense,"start":at,"contact":impact_x,"end":lan.position.x,"y":lan.position.y,"result":result,"hp":lan.combat_stats.health,"distance":(lan.position.x-impact_x)*side}
	samples.append(row)
	print("PUSH ",JSON.stringify(row))
	return row

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.boss
	lan=room.player
	deer.set_physics_process(false)
	deer.terrain.advance(2.4)
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target,outcome):
		if result<0:
			result=outcome
			impact_x=lan.position.x)
	for side in [-1.0,1.0]:
		for index in 4:
			var centre:=await trial(index,640,side)
			check(centre.result==CombatHitResult.Type.NORMAL_HIT and centre.distance>85 and centre.distance<270,"Move %d side %d has meaningful bounded push on a real hit" % [index,side])
			check(is_equal_approx(centre.y,415),"One central mistake still leaves the player on the summit")
			var edge:=await trial(index,170 if side<0 else 1110,side)
			check(edge.result==CombatHitResult.Type.NORMAL_HIT and edge.y>445,"The same hit near edge %d loses high ground, move %d" % [side,index])
			if side>0 and index==0: await capture("rush_edge_push")
		var miss:=await trial(2,170 if side<0 else 1110,side,"early")
		check(miss.result==CombatHitResult.Type.PARRY_FAILURE and miss.distance>65 and miss.y>435,"Early K retains partial guard but loses summit space, side %d" % side)
		var parry:=await trial(2,640,side,"parry")
		check(parry.result==CombatHitResult.Type.PARRY_SUCCESS and absf(parry.distance)<20 and parry.hp==100,"Successful real K does not inherit hit punishment")
		var dodge:=await trial(2,640,side,"dodge")
		check(dodge.hp==100 and dodge.result!=CombatHitResult.Type.NORMAL_HIT,"Successful real L preserves evasion")
	# Returning leaf pushes in its current travel direction even after the body crosses.
	reset_pair(640,1)
	deer.start_move(3,900)
	deer.pressure.release_leaf()
	var leaf: Node2D=deer.pressure.projectiles.back()
	leaf.flight=1.8
	leaf._sync_visual()
	check(leaf.hitbox.attack.knockback_direction==-1,"Returning leaf carries its own impact direction, not the caster position")
	deer.cancel_duel(false)
	deer.position=Vector2(420,415)
	deer.start_move(3,900)
	deer.age=DeerDuelBoss.LEAF_RELEASE
	deer._duel_leaf()
	deer.age=DeerDuelBoss.LEAF_RELEASE+1.8
	deer._duel_leaf()
	check(deer.attack_hitbox.attack.knockback_direction==-1,"Single-move practice uses the same returning-leaf impact direction")
	var file:=FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("root_knockback.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"\t"))
	file.close()
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER ROOT KNOCKBACK")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

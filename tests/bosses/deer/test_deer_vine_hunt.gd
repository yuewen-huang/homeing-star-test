extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var contacts: Array = []
var moves: Array[StringName] = []
var groups: Array[StringName] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_J,KEY_K,KEY_W,KEY_I]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func walk_to(x: float) -> void:
	if absf(x-lan.position.x)>4: Input.action_press(&"ui_right" if x>lan.position.x else &"ui_left")

func safe_gap() -> float:
	var best := lan.position.x
	var distance := INF
	for x in range(45,1235,5):
		if deer.arena.hazards.any(func(h): return absf(h.x-x)<49): continue
		if absf(x-lan.position.x)<distance:
			distance=absf(x-lan.position.x)
			best=x
	return best

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func route(x: float, difficulty: int) -> void:
	release()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)
	deer.restart_duel()
	deer.wait_left=999
	deer.pressure.selected=3
	deer.position=Vector2(820 if x<640 else 360,555)
	lan.reset_after_map_fall(Vector2(x,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	for f in 4: await physics_frame
	moves.clear()
	contacts.clear()
	groups.clear()
	deer.start_phrase(3)
	var gap := NAN
	var rush_k := false
	var sweep_k := false
	var jumped := false
	var opening_seen := false
	var early_opening := false
	var lock := Vector2.INF
	var stable := true
	var live_during_setup := false
	var elapsed := 0.0
	var snapshots := {}
	var hp: int = deer.combat_stats.health
	for f in 600:
		release()
		elapsed=f/60.0
		if deer.arena.burst_count>0 and not deer.arena.hazards.is_empty():
			if is_nan(gap): gap=safe_gap()
			walk_to(gap)
		if deer.move==&"hunt_rush_step" and not deer.arena.probes().is_empty(): live_during_setup=true
		if deer.move==&"rush" and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295 and not rush_k:
			key(KEY_K,true)
			rush_k=true
		if deer.move==&"vine_return" and deer.age>=.23:
			key(KEY_W,true)
			jumped=true
		if deer.move==&"sweep" and deer.opening<=0:
			if lock==Vector2.INF: lock=Vector2(deer.position.x,deer.direction)
			else: stable=stable and lock==Vector2(deer.position.x,deer.direction)
			if deer.age>=.48 and not sweep_k:
				key(KEY_K,true)
				sweep_k=true
		if deer.opening>0:
			early_opening=early_opening or not moves.has(&"sweep")
			opening_seen=true
			var delta: float = deer.position.x-lan.position.x
			if absf(delta)>115: walk_to(deer.position.x-signf(delta)*100)
			else:
				lan.facing_direction=signf(delta)
				if f%10==0: key(KEY_J,true)
		if x==380 and difficulty==BattleAssistSettingsService.Difficulty.HARD:
			var label := String(deer.move)
			if deer.move==&"forest_raise" and deer.age<.6: label=""
			if deer.move==&"vine_return" and deer.age<.58: label=""
			if label!="" and not snapshots.has(label):
				snapshots[label]=true
				await capture(label)
		await physics_frame
		if opening_seen and deer.opening<=0: break
	release()
	print("HUNT ROUTE x=",x," difficulty=",difficulty," health=",lan.combat_stats.health," damage=",hp-deer.combat_stats.health," seconds=",elapsed," contacts=",contacts," moves=",moves)
	check(lan.combat_stats.health==100,"Move to a gap, K, jump, K survives: x=%s difficulty=%s" % [x,difficulty])
	check(moves==[&"hunt_approach",&"forest_raise",&"hunt_rush_step",&"rush",&"vine_return",&"sweep"],"Full hunt runs through all authored beats")
	check(not early_opening and opening_seen,"No free opening interrupts the hunt; finisher grants recovery")
	check(jumped and rush_k and sweep_k and stable,"Jump/defense transitions are reachable and sweep is committed")
	check(contacts.any(func(c): return c.move==&"rush" and c.result==CombatHitResult.Type.PARRY_SUCCESS),"Rush demands and receives a real parry")
	check(deer.combat_stats.health<hp,"Real J reaches the earned finisher window")
	check(groups.all(func(g): return g==groups[0]),"One ordinary-difficulty parry group is preserved")
	check(live_during_setup,"The deer repositions while the pillar field remains dangerous")
	deer.cancel_duel()

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): room.select_boss(i)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.boss
	lan=room.player
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	deer.move_started.connect(func(id): moves.append(id); groups.append(deer.get_parry_chain_key()))
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append({"move":deer.move,"result":result}))
	for x in [80.0,380.0,800.0,1200.0]: await route(x,BattleAssistSettingsService.Difficulty.HARD)
	for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL,BattleAssistSettingsService.Difficulty.NIGHTMARE]: await route(380,difficulty)
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.start_phrase(3)
	var id: StringName=deer.move
	var health: int=deer.combat_stats.health
	var skill := SkillHitContext.new(&"lan_special_attack",45)
	skill.poise_damage=15
	deer.receive_skill_hit(skill,lan.position)
	check(deer.combat_stats.health==health-45 and deer.combat_stats.poise==165,"Ordinary skill retains full damage and poise")
	check(deer.move==id and deer.pressure.active and deer.opening==0,"Ordinary skill cannot delete the hunt")
	deer.pressure.active=false
	deer._recover(1.5)
	deer._update_opening(.2)
	var opening: float=deer.opening
	var recovery_age: float=deer._recovery_age
	deer.receive_skill_hit(skill,lan.position)
	check(deer.opening==opening and deer._recovery_age==recovery_age,"Skill hits cannot restart ordinary recovery to pin the deer indefinitely")
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise)
	check(deer.poise_broken and not deer.pressure.active and deer.stagger_remaining>=4.9,"Real break still cancels the hunt and grants five seconds")
	check(deer.arena.hazards.is_empty() and deer.vine.points.is_empty(),"Poise break clears every owned threat")
	deer.restart_duel()
	check(not deer.pressure.active and deer.arena.hazards.is_empty(),"Retry resets hunt state")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE HUNT")

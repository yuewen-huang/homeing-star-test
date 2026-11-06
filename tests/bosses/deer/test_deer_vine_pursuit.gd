extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var contacts: Array = []
var moves: Array = []

func key(code: int, down: bool) -> void:
	var e:=InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.pressed=down
	Input.parse_input_event(e)
func release() -> void:
	for code in [KEY_K,KEY_J,KEY_E,KEY_L,KEY_W]: key(code,false)
	for action in [&"ui_left",&"ui_right"]: Input.action_release(action)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func setup_at(boss_x: float, player_x: float) -> void:
	release()
	deer.restart_duel()
	deer.position=Vector2(boss_x,555)
	deer.wait_left=999
	lan.reset_after_map_fall(Vector2(player_x,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	contacts.clear()
	moves.clear()

func plow_route(boss_x: float, player_x: float, guard: bool, difficulty: int) -> void:
	setup_at(boss_x,player_x)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)
	deer.pressure.selected=0
	deer.start_phrase(0)
	var guarded_run:=false
	var guarded_lift:=false
	var source_frames: Dictionary={}
	var captured: Dictionary={}
	var group_keys: Dictionary={}
	for f in 250:
		release()
		if deer.move==&"plow":
			var lift_at: float=deer.plow.PREP+deer.plow.run_time+deer.plow.SET
			if guard and deer.age>=deer.plow.PREP and absf(deer.position.x-lan.position.x)<260 and not guarded_run:
				key(KEY_K,true)
				guarded_run=true
			if guard and difficulty!=BattleAssistSettingsService.Difficulty.NORMAL and deer.age>=lift_at-.05 and not guarded_lift:
				key(KEY_K,true)
				guarded_lift=true
			var body=deer.authored_body
			if body.PLOW.has(body.clip):
				var frame: int=body.entry_data().source_frames[body.source_frame]
				source_frames[frame]=true
				if boss_x<player_x and guard and frame in [7,15,18,21,30] and not captured.has(frame):
					captured[frame]=true
					await capture("pursuit_plow_%02d" % (frame+1))
			group_keys[deer.get_parry_chain_key()]=true
		await physics_frame
		if deer.opening>0: break
	check(deer.opening>0 and deer.move==&"pursuit_rest", "Plow ends with a real punish window")
	check(group_keys.size()==1, "Charge and lift share one normal-assist group")
	check(source_frames.size()==32, "Combat samples every authored cell including recovery")
	if guard:
		check(lan.combat_stats.health==100 and contacts.size()>=2, "Both real horn contacts can be parried: %.0f -> %.0f" % [boss_x,player_x])
		check(deer.defense_credit==2, "Two actual parries immediately break two beads")
	else: check(lan.combat_stats.health<100, "Unguarded charge really damages the player")
	check(deer.position.x>=deer.world_min_x+80 and deer.position.x<=deer.world_max_x-80, "Charge remains inside arena bounds")
	print("PLOW_ROUTE "+JSON.stringify({"boss":boss_x,"player":player_x,"guard":guard,"hp":lan.combat_stats.health,"contacts":contacts,"frames":source_frames.keys()}))

func crossing_route(boss_x: float, player_x: float) -> void:
	setup_at(boss_x,player_x)
	deer.pressure.selected=4
	deer.start_phrase(4)
	var parried:=false
	var crossed:=false
	var captured:=false
	var side:=signf(player_x-boss_x)
	for f in 320:
		release()
		if deer.move==&"rush" and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295 and not parried:
			key(KEY_K,true)
			parried=true
		if deer.move==&"vine_return":
			crossed=crossed or (deer.position.x-player_x)*side>100
			if deer.age>=.23: key(KEY_W,true)
			if boss_x<player_x and deer.age>=.58 and not captured:
				captured=true
				await capture("pursuit_original_rush_return")
		await physics_frame
		if deer.opening>0: break
	check(moves.has(&"rush") and moves.has(&"vine_return") and not moves.has(&"plow"), "Original crossing rush keeps its own animation and low return")
	check(crossed and deer.opening>0, "Original rush crosses to the far side and completes its return")
	check(lan.combat_stats.health==100 and contacts.any(func(c): return c.result==CombatHitResult.Type.PARRY_SUCCESS), "K then jump answers the restored original rush in both directions")
	check(deer.defense_credit==1, "Parry plus low-vine avoidance earns one defended exchange")

func other_group(kind: int, expected: StringName) -> void:
	setup_at(820,630)
	deer.pressure.selected=kind
	deer.start_phrase(kind)
	var live_field:=false
	for f in 440:
		await physics_frame
		live_field=live_field or not deer.arena.probes().is_empty()
		if deer.opening>0: break
	check(moves.has(expected) and deer.opening>0, "Existing group completes in the new controller: "+String(expected))
	if kind in [2,3]: check(live_field, "Field keeps real collision until its authored finish: "+String(expected))
	check(not deer.poise_broken and deer.arena.hazards.is_empty(), "Group finishes without hidden break or leftover hazards")

func mixed_route() -> void:
	setup_at(820,660)
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(true) # Only for long selection coverage; contact routes above use real health.
	deer.pressure.selected=-1
	deer._rng.seed=53117
	deer.wait_left=0
	for f in 4200:
		await physics_frame
		if deer.pressure.completed>=12: break
	var repertoire: Array[StringName]=[&"rush",&"vine_return",&"plow",&"sweep",&"forest_raise",&"drop",&"leaf"]
	check(repertoire.all(func(id): return moves.has(id)), "Continuous AI uses the complete retained ordinary repertoire, including drop and leaf")
	check(not moves.has(&"sky_cast"), "Full-health ordinary exchanges never select the cinematic ultimate")
	check(deer.pressure.completed>=12 and deer.pressure.decisions.all(func(d): return d.step<=2), "Twelve autonomous exchanges finish with at most two groups each")
	print("PURSUIT_MIXED "+JSON.stringify({"moves":moves,"decisions":deer.pressure.decisions}))
	assist.set_player_invincible(false)

func drop_route(boss_x: float, player_x: float, avoid: bool) -> void:
	room.select_combo(6)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	setup_at(boss_x,player_x)
	deer.start_phrase(deer.pressure.selected)
	var apex:=555.0
	var source_frames: Dictionary={}
	var live_field:=false
	var captured: Dictionary={}
	var escape_x:=player_x+(180 if player_x<640 else -180)
	for f in 250:
		release()
		if avoid and absf(lan.position.x-escape_x)>4:
			Input.action_press(&"ui_right" if escape_x>lan.position.x else &"ui_left")
		await physics_frame
		# The user's drawing contains the leap inside the canvas; the root stays
		# grounded. Measure the visible torso, not an extra procedural Y offset.
		apex=minf(apex,deer.position.y+deer.authored_body.chest_offset().y)
		if String(deer.authored_body.clip).begins_with("leap_"):
			var frame: int=deer.authored_body.entry_data().source_frames[deer.authored_body.source_frame]
			source_frames[frame]=true
		live_field=live_field or not deer.arena.probes().is_empty()
		if avoid and boss_x>player_x and deer.move==&"drop":
			var label: String="drop_apex" if deer.age>=.62 and deer.age<.82 else "drop_eruption" if not deer.arena.probes().is_empty() else ""
			if label!="" and not captured.has(label):
				captured[label]=true
				await capture(label)
		if deer.opening>0: break
	check(moves.has(&"drop") and apex<350 and live_field and deer.opening>0, "Restored high jump lands, erupts and finishes: %.0f" % player_x)
	check(source_frames.size()==32, "Restored jump keeps all 32 authored cells including landing recovery")
	check(lan.combat_stats.health==100 if avoid else lan.combat_stats.health<100, "Jump landing and delayed pillars can be avoided, but punish standing still")
	check(deer.arena.hazards.is_empty() and not deer.poise_broken, "Drop completes its pillar lifetime before the opening")

func leaf_route(boss_x: float, player_x: float, guard: bool, red: bool) -> void:
	room.select_combo(7)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	setup_at(boss_x,player_x)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer._leaf_casts=2 if red else 0
	deer.start_phrase(deer.pressure.selected)
	var emitted:=false
	var reflected:=false
	var pressed:=false
	var travelled:=false
	var captured:=false
	var hp: int=deer.combat_stats.health
	for f in 320:
		release()
		for projectile in deer.pressure.projectiles.duplicate():
			if not is_instance_valid(projectile): continue
			emitted=true
			travelled=travelled or projectile.world_at(projectile.flight).distance_to(projectile.start)>90
			reflected=reflected or projectile.leaf_reflected
			if guard and not pressed and absf(projectile.world_at(projectile.flight).x-lan.position.x)<70:
				key(KEY_K,true)
				pressed=true
			if not captured and projectile.flight>.20 and not red and not guard:
				captured=true
				await capture("restored_leaf_flight")
		await physics_frame
		if deer.opening>0: break
	check(moves.has(&"leaf") and emitted and travelled and deer.opening>0, "Leaf is a moving independent projectile, not only a casting animation")
	check(lan.combat_stats.health==100 if guard else lan.combat_stats.health<100, "Restored leaf uses real player damage and K settlement")
	if red: check(reflected and deer.combat_stats.health==hp-24, "Red leaf retains one real reflection hit on its caster")
	elif guard: check(deer.defense_credit==1, "Ordinary leaf parry earns defense credit without restoring poise break")
	check(deer.pressure.projectiles.is_empty() and not deer.poise_broken, "Leaf finishes or is consumed cleanly")

func ultimate_route() -> void:
	setup_at(220,680)
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(true)
	deer.pressure.selected=-1
	deer.start_phrase(4)
	deer.combat_stats.apply_health_damage(801)
	var premature:=false
	var complete_cast:=false
	var waves:=0
	for f in 1500:
		await physics_frame
		if deer.move==&"sky_cast":
			premature=premature or not moves.has(&"vine_return") or deer.pressure.completed<1
			waves=maxi(waves,deer.arena.wave_count)
		if moves.has(&"pursuit_sky_end") and deer.opening>0: complete_cast=true
		if complete_cast and deer.pressure.completed>=4: break
	check(moves.count(&"sky_cast")==1 and not premature, "Half-health ultimate waits for the exchange and triggers only once")
	check(complete_cast and waves==4, "Ultimate completes four rain phrases, return and its separate finish window")
	var ultimate_decisions: Array=deer.pressure.decisions.filter(func(d): return d.group==3)
	check(ultimate_decisions.size()==1 and ultimate_decisions[0].step==1, "Ultimate never occupies an ordinary follow-up slot")
	deer.restart_duel()
	check(not deer.pressure.ultimate_used, "Retry rearms the once-per-fight ultimate")
	assist.set_player_invincible(false)

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_pursuit_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.deer
	lan=room.player
	deer.move_started.connect(func(id): moves.append(id))
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append({"contact":deer.plow.contact,"result":result}))
	await plow_route(220,800,true,BattleAssistSettingsService.Difficulty.NORMAL)
	await plow_route(850,380,true,BattleAssistSettingsService.Difficulty.HARD)
	await plow_route(420,48,true,BattleAssistSettingsService.Difficulty.NIGHTMARE)
	await plow_route(800,1230,false,BattleAssistSettingsService.Difficulty.NORMAL)
	await crossing_route(220,680)
	await crossing_route(1060,600)
	await other_group(1,&"sweep")
	await other_group(2,&"forest_raise")
	await other_group(3,&"sky_cast")
	await drop_route(820,380,true)
	await drop_route(360,800,true)
	await drop_route(820,380,false)
	await leaf_route(820,380,false,false)
	await leaf_route(360,800,true,false)
	await leaf_route(820,380,true,true)
	await mixed_route()
	await ultimate_route()
	check(not room.segment_row.visible, "Combat hides source-only segment controls from the player HUD")
	setup_at(220,850)
	deer.set_physics_process(false)
	deer.pressure.selected=-1
	deer._rng.seed=53117
	var offered: Dictionary={}
	for i in 100: offered[deer.pressure.choose_group()]=true
	check(offered.has(0) and offered.has(4), "Distance-based AI can choose both original rush and new uppercut")
	deer.position.x=850
	lan.position.x=1220
	deer.start_phrase(4)
	deer.pressure.reposition(.5)
	check(deer.move==&"plow", "AI chooses the stopping uppercut where a wall prevents crossing")
	deer.position.x=220
	lan.position.x=850
	deer.start_phrase(0)
	deer.plow.start()
	var fixed_destination: float=deer.plow.destination
	var fixed_side: float=deer.plow.side
	lan.position.x=90
	deer.age=.4
	deer.plow.execute()
	check(deer.plow.destination==fixed_destination and deer.plow.side==fixed_side, "Crossing behind after the tell cannot swivel or retarget the committed charge")
	deer.pressure.groups_used=1
	deer.position.x=600
	lan.position.x=100
	deer.pressure.finish_move(0)
	check(deer.pressure.active and deer.move==&"pursuit_step" and deer.pressure.groups_used==2, "An escaped player triggers another bounded decision")
	deer.pressure.groups_used=2
	deer.move=&"plow"
	deer.pressure.finish_move(0)
	check(not deer.pressure.active and deer.opening>0, "At most two groups; no endless pursuit")
	setup_at(820,660)
	deer.set_physics_process(false)
	deer.start_phrase(0)
	var hp: int=deer.combat_stats.health
	var skill:=SkillHitContext.new(&"lan_special_attack",45)
	skill.poise_damage=500
	deer.receive_skill_hit(skill,lan.position)
	check(deer.combat_stats.health==hp-45 and not deer.poise_broken and deer.pressure.active, "Skill damage stays full without deleting the exchange or causing a long break")
	for i in DeerDuelBoss.COUNTER_PARRIES: deer.on_attack_parried(CombatAttackData.new(StringName("bead_%d" % i),deer,0,0,0,0),deer.position)
	check(deer.counter_ready and not deer.poise_broken and deer.opening==0, "Six successful parries store one reward without stunning the boss")
	check(not deer.can_offer_break_empower(), "Stored throw requires a genuine finish window")
	deer.pressure.active=false
	deer.move=&"pursuit_rest"
	deer._recover(.85)
	lan.facing_direction=1
	check(lan.find_throw_target()==deer, "Existing E targeting finds the earned execution")
	hp=deer.combat_stats.health
	key(KEY_E,true)
	for f in 3: await physics_frame
	key(KEY_E,false)
	for f in 50: await physics_frame
	check(not deer.counter_ready and deer.combat_stats.health==hp-200, "Real E consumes one reward for 200 damage, without break amplification")
	check(deer.stagger_remaining<=0 and not deer.poise_broken, "Execution never creates a five-second dummy")
	deer.restart_duel()
	check(not deer.counter_ready and deer.defense_credit==0 and deer.arena.hazards.is_empty(), "Retry clears reward and hazards")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE PURSUIT")

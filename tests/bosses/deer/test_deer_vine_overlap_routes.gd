extends "../../support/harness.gd"
## Diagnostic routes through legal two-group phrases, on the production forest floor.
## Fixed follow-up selection replaces RNG only; all movement and defense use real input.
var room: Chapter1DeerBossRoom
var deer: Node2D
var lan: LanPlayer
var reports: Array = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K, KEY_L, KEY_W, KEY_J]: key(code, false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func walk_to(x: float) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	if absf(lan.position.x-x)>3:
		Input.action_press(&"ui_right" if x>lan.position.x else &"ui_left")

func route(first: int, second: int, delay: float, defend := true, expect_safe := true) -> void:
	release()
	deer.restart_duel()
	deer.position=Vector2(900,555)
	deer.wait_left=999
	deer.manual_control=false
	deer.pressure.selected=-1
	lan.reset_after_map_fall(Vector2(1250,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	await wait_frames(3)
	deer.start_phrase(first)
	var forced := false
	var entered := false
	var pressed := {}
	var elapsed := 0.0
	var overlap := 0
	var body_with_field := 0
	var last_move := &""
	var events: Array = []
	var initial_hp: int=lan.combat_stats.health
	var previous_hp := initial_hp
	var boss_hp := 0
	var hits := 0
	var punish_start := -1.0
	var first_hit := -1.0
	var punished := false
	var field_target := 1310.0
	var drop_target := 1430.0
	for frame in 900:
		elapsed=frame/60.0
		key(KEY_K,false)
		key(KEY_W,false)
		key(KEY_J,false)
		if deer.move!=last_move:
			events.append({"at":elapsed,"move":deer.move,"player_x":lan.position.x,"boss_x":deer.position.x})
			last_move=deer.move
		if deer.move==&"pursuit_step" and deer.pressure.groups_used==2 and not forced:
			deer.pressure.group=second
			forced=true
		if not deer.arena.probes().is_empty():
			if deer.move in [&"plow",&"rush",&"drop",&"sweep"]: body_with_field+=1
			if deer.attack_hitbox.attack!=null: overlap+=1
		if not deer.pressure.projectiles.is_empty() and deer.attack_hitbox.attack!=null: overlap+=1
		if defend and deer.opening<=0:
			if first==2 and deer.move==&"forest_raise" and deer.age>=.45+delay:
				walk_to(field_target)
			elif first==2 and not forced:
				if pressed.has("moved"): walk_to(field_target)
			if first==2 and deer.move==&"forest_raise" and deer.age>=.45+delay: pressed["moved"]=true
			if first==6 and deer.move==&"leaf" and deer.age>=.76+delay and not pressed.has("leaf_jump"):
				key(KEY_W,true)
				pressed["leaf_jump"]=true
			if deer.move==&"plow":
				walk_to(lan.position.x)
				var lift_at: float=deer.plow.PREP+deer.plow.run_time+deer.plow.SET
				if deer.age>=deer.plow.PREP and absf(deer.position.x-lan.position.x)<260 and not pressed.has("plow"):
					key(KEY_K,true)
					pressed["plow"]=true
				if deer.age>=lift_at-.05 and not pressed.has("lift"):
					key(KEY_K,true)
					pressed["lift"]=true
			if deer.move==&"rush":
				walk_to(lan.position.x)
				if deer.age>=.68 and absf(deer.position.x-lan.position.x)<295 and not pressed.has("rush"):
					key(KEY_K,true)
					pressed["rush"]=true
			if deer.move==&"vine_return" and deer.age>=.23 and not pressed.has("return"):
				key(KEY_W,true)
				pressed["return"]=true
			if deer.move==&"drop" and deer.age>=delay:
				walk_to(drop_target)
		if deer.opening>0 and not entered:
			entered=true
			boss_hp=deer.combat_stats.health
			punish_start=elapsed
			events.append({"at":elapsed,"opening":deer.opening,"distance":absf(deer.position.x-lan.position.x),"hazards":deer.arena.hazards.size(),"leaves":deer.pressure.projectiles.size()})
		if entered:
			if deer.opening<=0: break
			var side: float=signf(deer.position.x-lan.position.x)
			if absf(deer.position.x-lan.position.x)>125:
				walk_to(deer.position.x-side*120)
			else:
				walk_to(lan.position.x)
				if not punished:
					key(KEY_J,true)
					punished=true
		await physics_frame
		if lan.combat_stats.health!=previous_hp:
			events.append({"at":elapsed,"hp":lan.combat_stats.health,"move":deer.move,"age":deer.age,"x":lan.position.x})
			previous_hp=lan.combat_stats.health
		if entered and deer.combat_stats.health<boss_hp and first_hit<0:
			first_hit=elapsed-punish_start
			hits+=1
		if lan.combat_stats.health<=0: break
	release()
	var report := {"first":first,"second":second,"delay":delay,"defend":defend,"hp":lan.combat_stats.health,"punish":punished,"hit":hits,"first_hit_after_open":first_hit,"body_with_thorns_frames":body_with_field,"active_overlap_frames":overlap,"events":events}
	reports.append(report)
	print("VINE_OVERLAP "+JSON.stringify(report))
	check(forced and entered,"Two legal groups reach their natural recovery")
	if defend:
		check((lan.combat_stats.health==initial_hp)==expect_safe,"Real input %s at delay %.2f"%["avoids both groups" if expect_safe else "punishes a late response",delay])
		if expect_safe: check(hits>0,"A real J reaches the boss during the natural opening")
	else:
		check(lan.combat_stats.health<initial_hp,"Ignoring the same overlap deals real damage")

func run() -> void:
	var memory := use_memory_progress()
	var movie := "--movie" in OS.get_cmdline_user_args()
	if movie:
		memory.mark_completed(SaveProgressService.STORY_C1_DEER_DEFEATED)
		(root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested=true
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro:=WindSightingComic.new()
	var packed:=PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	room.encounter._spawn_phase(3,900)
	room.encounter.start()
	deer=room.deer
	lan=room.player
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	if not movie:
		await route(2,0,.10)
		await route(2,0,.32)
		await route(2,4,.10)
	await route(6,5,.16)
	if not movie:
		await route(2,0,.42,true,false)
		await route(2,0,.10,false)
	FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("routes.json"),FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE OVERLAP ROUTES")

extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var results: Array=[]
func key(code: int, down: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
func setup_at(x:=250.0, player_x:=650.0) -> void:
	key(KEY_K,false)
	key(KEY_L,false)
	deer.restart_duel()
	deer.transform_left=0
	deer.invulnerable=false
	deer.position=Vector2(x,555)
	deer.wait_left=999
	lan.reset_after_map_fall(Vector2(player_x,555))
	lan.combat_stats.max_health=1000
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	results.clear()
func step(count: int) -> void:
	for i in count:
		deer.wait_left=999
		await physics_frame
func core_route(parries: int, difficulty: int, dodge := false) -> void:
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)
	deer.start_spell(4)
	var spell: Node2D=deer.spells.back()
	var sent := {}
	var last_contacts := 0
	var last_successes := 0
	var last_explosions := 0
	var slow_seen := false
	for f in 650:
		key(KEY_K,false)
		key(KEY_L,false)
		deer.wait_left=999
		if not is_instance_valid(spell): break
		var index: int=spell.core_contacts
		var next: float=2.06+index*.22
		if dodge and not sent.has("dodge") and spell.age>=1.99:
			key(KEY_L,true)
			sent["dodge"]=true
		slow_seen=slow_seen or deer.action_clock.dodge_remaining>0
		if index<parries and not sent.has(index) and spell.age>=next-.145:
			key(KEY_K,true)
			sent[index]=true
		last_contacts=spell.core_contacts
		last_successes=spell.core_successes
		last_explosions=spell.core_explosions
		if f in [60,130,215]: await capture("wind_core_%d_%d"%[parries,f])
		await physics_frame
	key(KEY_K,false)
	key(KEY_L,false)
	check(last_contacts==9,"Wind core resolves all nine contacts")
	var expected := 9 if difficulty==BattleAssistSettingsService.Difficulty.NORMAL and parries>0 else parries
	check(last_successes==expected,"Real K successes: expected %d, got %d"%[expected,last_successes])
	check(last_explosions==9-last_successes,"Exactly one explosion per un-parried contact")
	if not dodge: check(lan.combat_stats.health<1000 if expected<9 else lan.combat_stats.health==1000,"Failures hurt and complete defense avoids damage")
	if dodge:
		check(results.has(CombatHitResult.Type.EVADED),"Real L evades wind-core contact through the shared route")
		check(last_successes==0 and last_explosions==9,"Dodging avoids contact but earns no parry cancellation")
		check(slow_seen,"Detached spell perfect dodge slows the encounter clock")
	print("CORE_ROUTE "+JSON.stringify({"inputs":parries,"successes":last_successes,"explosions":last_explosions,"hp":lan.combat_stats.health,"results":results}))
func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_wind_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.deer
	lan=room.player
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): results.append(result))
	var frames: Dictionary={}
	for f in 210:
		frames[deer.human.source_frame]=true
		if f in [50,115,185]: await capture("wind_transform_%d"%f)
		await physics_frame
	check(frames.size()>=32 and deer.transform_left==0,"All 32 transformation cells reach the human form")
	for index in 4:
		setup_at()
		deer.start_spell(index)
		await step(45)
		var spell: Node2D=deer.spells.back()
		await capture("wind_%s_warning"%spell.kind)
		await step(60)
		check(is_instance_valid(spell) and not spell.finished,"Detached spell survives body recovery: %d"%index)
		await capture("wind_%s_active"%spell.kind)
		if index==1:
			check(spell.objects.size()==14,"Two converging tornadoes and twelve uneven roots")
		if index==2:
			await step(95)
			check(spell.objects.size()==7,"Seven meteor storms coexist without a two-storm cap")
		if index==3:
			check(spell.objects.size()==6,"One deer phantom leaves a five-section wind path")
		await step(520)
		check(deer.spells.is_empty(),"Hazards expire naturally: %d"%index)
	await core_route(0,BattleAssistSettingsService.Difficulty.HARD)
	await core_route(1,BattleAssistSettingsService.Difficulty.NORMAL)
	await core_route(6,BattleAssistSettingsService.Difficulty.HARD)
	await core_route(0,BattleAssistSettingsService.Difficulty.HARD,true)
	setup_at()
	deer.start_spell(1)
	await step(100)
	var tornado: Node2D=deer.spells.back()
	lan.reset_after_map_fall(Vector2(tornado.objects[0].fx._x,430))
	await step(50)
	check(tornado.capture_throw.length()>500,"Caught tornado produces a real randomized launch")
	check(lan.combat_stats.health<1000,"Tornado/root contact deals real damage without grace immunity")
	await capture("wind_tornado_throw")
	setup_at()
	deer.tail_variant=1
	deer.start_spell(3)
	await step(140)
	var old_phantom: Node2D=deer.spells.back()
	check(old_phantom.tail_type==1,"Second deer flash uses the signalled updraft variation")
	await capture("wind_phantom_updraft")
	deer.start_spell(3)
	await step(40)
	check(not is_instance_valid(old_phantom) or old_phantom.finished,"Next deer flash replaces its prior path")
	setup_at()
	deer.start_spell(2)
	await step(130)
	var meteors: Node2D=deer.spells.back()
	deer.start_spell(0)
	await step(50)
	check(is_instance_valid(meteors) and deer.has_spell("meteors") and deer.has_spell("leaves"),"Meteor storms remain active across a leaf followup")
	await capture("wind_overlap")
	setup_at()
	deer.opening=0
	for i in 3:
		deer.round_casts=1
		deer.round_parried=true
		deer.round_damaged=false
		deer._finish_cast()
	check(deer.counter_ready and not deer.poise_broken,"Three clean exchanges offer a throw without poise stun")
	deer.position.x=700
	lan.reset_after_map_fall(Vector2(640,555))
	lan.facing_direction=1
	check(lan.find_throw_target()==deer,"The existing E contract targets the human form")
	var hp: int=deer.combat_stats.health
	key(KEY_E,true)
	await step(3)
	key(KEY_E,false)
	await step(80)
	check(not deer.counter_ready and deer.combat_stats.health==hp-200,"Real E consumes the earned throw for 200 damage")
	check(not deer.poise_broken and deer.stagger_remaining<=0,"E does not turn the human boss into a long stun dummy")
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	deer.wait_left=0
	for f in 3300: await physics_frame
	var used := {}
	for move in deer.move_history: used[move]=true
	check(used.size()==5,"Adaptive full-health combat selects all five ordinary spells")
	check(deer.move_history.count(&"core")>=2,"Wind core recurs as an ordinary spell, without ultimate health gate")
	check(deer.position.x>deer.world_min_x and deer.position.x<deer.world_max_x,"Active positioning remains in arena")
	deer.restart_duel()
	check(deer.spells.is_empty() and not deer.counter_ready,"Retry clears all spell contacts and rewards")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	lan.combat_stats.max_health=100
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER WIND")

extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
var lan: LanPlayer
var parries := 0
var parry_openings: Array[float] = []
var moves: Array[StringName] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func reset_pair() -> void:
	key(KEY_K,false)
	room._combat_result=""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.terrain.advance(2.4)
	deer.position=Vector2(900,415)
	lan.reset_after_map_fall(Vector2(420,415))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	deer.wait_left=0
	parries=0
	parry_openings.clear()
	moves.clear()

func phrase(index: int) -> void:
	deer.pressure.active=true
	deer.pressure.serial+=1
	deer.pressure.phrase=index
	deer.pressure.step=0
	deer.pressure.transition_age=0
	deer.pressure.transition_duration=0
	deer.pressure.tactic=&"press"
	deer.pressure.step_target=NAN

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer=room.adapter.boss
	lan=room.player
	room.set_physics_process(false)
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result):
		if result==CombatHitResult.Type.PARRY_SUCCESS:
			parries+=1
			parry_openings.append(deer.opening))
	deer.move_started.connect(func(id): moves.append(id))
	reset_pair()
	check(deer.combat_stats.max_health==1800 and deer.combat_stats.max_poise==200,"Phase two has a separate encounter budget")
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.terrain.advance(.8)
	deer.interrupt_with_special()
	deer.terrain.advance(1.6)
	check(is_equal_approx(deer.ground_y_at(640),415),"Interrupting deer during entry cannot stop the stage-owned platform halfway")
	reset_pair()
	for t in [0.5,4.0,7.0]:
		deer.contest_wave.clock=t
		deer.pressure.choose_phrase(480)
		check(deer.pressure.tactic==(&"approach" if t<3.2 else (&"press" if t<6 else &"turn")),"Same position changes tactics with root wave clock %.1f" % t)
	for side in [-1,1]:
		reset_pair()
		deer.position=Vector2(-200 if side<0 else 1450,555)
		lan.position=Vector2(1550 if side<0 else -220,555)
		deer._contest_selection(.02)
		var aim:=deer._aim
		check(deer.move==&"drop" and aim>=260 and aim<=1020,"Off-platform deer locks a summit landing from side %d" % side)
		lan.position.x=640
		deer.age=DeerDuelBoss.DROP_CONTACT+.02
		deer._duel_drop()
		check(deer.position.is_equal_approx(Vector2(aim,415)),"Landing stays on new platform and ignores later player movement")
		check(deer.summit_claim.running and deer.summit_claim.clock==0,"A reclaim landing starts a warning, never instant roots")
	# Real K must not reactivate the old phase-two yield/recovery behavior.
	reset_pair()
	phrase(0)
	deer.set_physics_process(true)
	var pressed:=false
	var crossed:=false
	var overlap:=false
	for f in 650:
		key(KEY_K,false)
		if not pressed and deer.move==&"rush" and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295:
			pressed=true
			key(KEY_K,true)
		await physics_frame
		if parries>0 and deer.move==&"rush": crossed=crossed or deer.position.x<lan.position.x
		if not deer.pressure.projectiles.is_empty() and deer.move!=&"leaf": overlap=true
		if deer.pressure.completed>0: break
	check(parries>=1 and not parry_openings.is_empty() and parry_openings[0]==0,"Real ordinary parry awards no recovery on the summit")
	check(crossed and not deer.contest_recoil,"Parried rush completes its summit crossing without artificial yield")
	check(moves.size()>=3 and overlap,"Summit phrase continues while its detached leaf is flying")
	key(KEY_K,false)
	# Occupation keeps its drawn footprint, warns fully, allows the other half and expires.
	reset_pair()
	lan.set_physics_process(false)
	var claim:=deer.summit_claim
	claim.begin(480)
	var zone: Rect2=claim.footprint()
	print("CLAIM_FOOTPRINT ",zone)
	check(zone.size.x<550 and zone.end.x<1040,"Occupied area leaves a full alternate route across the summit")
	lan.position=Vector2(480,415)
	var hp:=lan.combat_stats.health
	claim.advance(.75)
	check(lan.combat_stats.health==hp,"Full visible root warning is harmless")
	await capture("root_claim_warning")
	claim.advance(.5)
	check(lan.combat_stats.health==hp-12,"Staying in the root footprint takes one unguardable hit")
	await capture("root_claim_active")
	hp=lan.combat_stats.health
	claim.advance(.1)
	check(lan.combat_stats.health==hp,"The occupation attack cannot repeatedly stun the player")
	check(not claim.begin(950),"A new landing cannot overwrite an existing warning or fill both sides")
	claim.advance(2.0)
	check(not claim.running,"Occupation clears on its own clock")
	await capture("root_claim_clear")
	lan.reset_after_map_fall(Vector2(980,415))
	lan.set_physics_process(false)
	claim.begin(480)
	hp=lan.combat_stats.health
	claim.advance(1.25)
	check(lan.combat_stats.health==hp,"Moving to the open summit half avoids the actual root geometry")
	reset_pair()
	lan.reset_after_map_fall(Vector2(480,415))
	lan.set_physics_process(true)
	# Let previous isolated hit feedback finish before measuring a fresh telegraph.
	for f in 20: await physics_frame
	claim.begin(480)
	hp=lan.combat_stats.health
	deer.wait_left=999
	deer.set_physics_process(true)
	var escape_action: StringName = &"ui_right" if claim.footprint().get_center().x<lan.position.x else &"ui_left"
	Input.action_press(escape_action)
	for f in 85:
		await physics_frame
	Input.action_release(escape_action)
	print("CLAIM_ESCAPE hp=",lan.combat_stats.health," start=",hp," x=",lan.position.x," zone=",claim.footprint()," clock=",claim.clock)
	var escaped: bool = lan.position.x<claim.footprint().position.x or lan.position.x>claim.footprint().end.x
	check(lan.combat_stats.health==hp and escaped,"Real movement toward the nearer marked edge escapes without teleporting or invulnerability")
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	# Roots and independent leaves respect terrain height and real interruption rewards.
	deer.position=Vector2(220,415)
	deer._starting_pressure_move=true
	deer.start_move(3,900)
	deer._starting_pressure_move=false
	phrase(2)
	deer.pressure.release_leaf()
	var leaf: Node2D=deer.pressure.projectiles.back()
	check(leaf.start.y<415 and leaf.start.y>350,"Detached leaf uses the elevated launch lane")
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise)
	check(deer.poise_broken and not deer.pressure.active and deer.pressure.projectiles.is_empty() and not claim.running,"True break clears body, leaves and summit roots for the reward window")
	check(deer.stagger_remaining>=4.9,"Phase two retains the accepted five-second break release")
	# Lowland danger is real, applies to either side and keeps one contact per pulse.
	reset_pair()
	lan.set_physics_process(false)
	lan.position=Vector2(-200,555)
	deer.position=Vector2(1450,555)
	var boss_hp:=deer.combat_stats.health
	hp=lan.combat_stats.health
	for f in 360: deer.contest_wave.advance(1.0/60)
	check(lan.combat_stats.health<=hp-32,"Camping lowland costs at least two meaningful root hits in one cycle")
	check(deer.combat_stats.health<=boss_hp-70,"Deer displaced to lowland also pays for root pulses")
	deer.restart_duel()
	check(not claim.running and deer.pressure.projectiles.is_empty() and deer.terrain.roots.size()==1,"Retry resets occupation and pressure, retaining one stage platform")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER ROOT PRESSURE")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

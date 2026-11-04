extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var contacts: Array[int] = []
var immediate_openings: Array[float] = []
var moves: Array[Dictionary] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_J,KEY_W,KEY_L,KEY_E]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func reset_pair(side := -1) -> void:
	release()
	room._combat_result = ""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.wait_left = 999
	deer.position.x = 820 if side < 0 else 360
	lan.reset_after_map_fall(Vector2(380 if side < 0 else 800,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	lan.facing_direction = -side
	contacts.clear()
	immediate_openings.clear()
	moves.clear()

func phrase(index: int) -> void:
	deer.pressure.active = true
	deer.pressure.serial += 1
	deer.pressure.phrase = index
	deer.pressure.step = 0
	deer.pressure.transition_duration = 0
	deer.pressure.transition_age = 0
	deer.pressure.step_target = NAN
	deer.wait_left = 0

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer = room.adapter.boss
	lan = room.player
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result):
		contacts.append(result)
		if result == CombatHitResult.Type.PARRY_SUCCESS: immediate_openings.append(deer.opening))
	deer.move_started.connect(func(id): moves.append({"move":String(id),"key":String(deer.get_parry_chain_key()),"gap":absf(lan.position.x-deer.position.x)}))
	check(deer.combat_stats.max_health == 1600 and deer.combat_stats.max_poise == 180,"New encounter owns its health/poise without nerfing player skills")
	for side in [-1,1]:
		reset_pair(side)
		phrase(2)
		var pressed := false
		var continued := false
		var crossed := false
		var leaf_overlap := false
		var origin := deer.position.x
		for frame in 650:
			key(KEY_K,false)
			if deer.move == &"rush" and not pressed and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295:
				key(KEY_K,true)
				pressed = true
			await physics_frame
			if contacts.has(CombatHitResult.Type.PARRY_SUCCESS) and deer.move == &"rush":
				continued = continued or deer.age > 1.0
				crossed = crossed or (deer.position.x-lan.position.x)*side>0
			if not deer.pressure.projectiles.is_empty() and deer.move != &"leaf" and deer.move != &"": leaf_overlap = true
			if deer.pressure.completed > 0:
				deer.wait_left = 999
				break
		check(pressed and contacts.count(CombatHitResult.Type.PARRY_SUCCESS)==1,"Real K lands exactly once on crossing rush, side %d" % side)
		check(not immediate_openings.is_empty() and immediate_openings[0]==0,"Ordinary parry does not award recovery, side %d" % side)
		check(continued and crossed and absf(deer.position.x-origin)>100,"Parried rush completes its crossing, side %d" % side)
		check(moves.size()>=3 and moves[0].key==moves[1].key and moves[1].key==moves[2].key,"Whole phrase retains one assisted-parry group, side %d" % side)
		check(leaf_overlap,"Body starts its follow-up while the released leaf is still flying, side %d" % side)
		check(deer.opening>0,"Only the completed phrase enters its normal punish window")
		await capture("phrase_end_%d" % side)
	# A deflected projectile is consumed independently of its caster's current action.
	reset_pair()
	phrase(1)
	var parried_leaf := false
	var leaf_press := false
	for frame in 350:
		key(KEY_K,false)
		for projectile: Node2D in deer.pressure.projectiles:
			if is_instance_valid(projectile) and not projectile.finished and not leaf_press and absf(projectile.world_at(projectile.flight).x-lan.position.x)<70:
				key(KEY_K,true)
				leaf_press = true
		await physics_frame
		if contacts.has(CombatHitResult.Type.PARRY_SUCCESS):
			parried_leaf = true
			break
	check(parried_leaf and deer.pressure.active and deer.opening==0,"Real K removes the leaf without cancelling the casting phrase")
	# True poise depletion still interrupts and preserves the five-second release.
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise)
	check(deer.poise_broken and not deer.pressure.active and deer.attack_probes().is_empty(),"Actual break cancels the phrase and every detached hazard")
	release()
	for frame in 120:
		await physics_frame
		if lan.defense_state == LanPlayer.DefenseState.NONE and lan.ground_action_state == LanPlayer.GroundActionState.NONE: break
	var hp := deer.combat_stats.health
	lan.facing_direction = signf(deer.position.x-lan.position.x)
	lan.position.x = deer.position.x-lan.facing_direction*100
	check(lan.update_throw_prompt()==deer,"E has an eligible broken target after the parry pose completes")
	print("E_READY defense=",lan.defense_state," ground=",lan.ground_action_state," air=",lan.air_state," break=",deer.stagger_remaining)
	key(KEY_E,true)
	for frame in 3: await physics_frame
	key(KEY_E,false)
	for frame in 60: await physics_frame
	check(deer.combat_stats.health==hp-300,"Real E keeps its full 200 damage plus break multiplier")
	check(not deer.break_empower_available,"Break E remains one redemption per window")
	deer.receive_attack_hit(CombatAttackData.new(&"pressure_test_hit",lan,10,3,0,0),lan.global_position)
	check(deer.short_stun_remaining>=.55 and deer.opening>=.65,"Repeated hits during break retain the intended pressure/stun reward")
	reset_pair()
	deer._leaf_casts = 2
	phrase(1)
	var reflected := false
	var red_pressed := false
	var reflected_hp := deer.combat_stats.health
	for frame in 420:
		key(KEY_K,false)
		for projectile: Node2D in deer.pressure.projectiles:
			if not is_instance_valid(projectile) or projectile.finished: continue
			reflected = reflected or projectile.leaf_reflected
			if not red_pressed and absf(projectile.world_at(projectile.flight).x-lan.position.x)<70:
				key(KEY_K,true)
				red_pressed = true
		await physics_frame
		if reflected and deer.opening>0: break
	check(reflected and deer.combat_stats.health==reflected_hp-DeerDuelBoss.REFLECT_DAMAGE,"Independent red leaf returns to the moving caster and settles once")
	check(not deer.pressure.active and deer.opening>=2.2,"A successful red reflection keeps its explicit counter opening")
	# Ordinary and hard difficulties share the visible phrase; normal assistance is not split per hit.
	reset_pair()
	phrase(2)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	for frame in 3: await physics_frame
	var old_key := deer.get_parry_chain_key()
	lan.parry_chain.begin(deer,lan.combat_clock)
	deer._finish_duel_move(1.0)
	for frame in 160:
		await physics_frame
		if deer.move==&"leaf": break
	check(deer.get_parry_chain_key()==old_key and lan.parry_chain.covers(deer,lan.combat_clock),"Normal assistance remains valid across natural follow-up selection")
	deer.cancel_duel()
	check(deer.pressure.projectiles.is_empty() and not deer.pressure.active,"Reset cancels controller and leaf ownership together")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER PRESSURE CONTRACTS AND INPUT")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

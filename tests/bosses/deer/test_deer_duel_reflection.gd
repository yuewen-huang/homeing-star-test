extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var contacts: Array[int] = []

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func release_inputs() -> void:
	for code in [KEY_K,KEY_J,KEY_W]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func reset_pair(side: int) -> void:
	release_inputs()
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
	room.set_physics_process(false)
	deer = room.adapter.boss
	lan = room.player
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	# Native input through the real Lan and boss clocks, in both facing directions.
	for side in [-1,1]:
		for scenario in 3:
			reset_pair(side)
			for f in 10: await physics_frame
			var boss_hp := deer.combat_stats.health
			var boss_poise := deer.combat_stats.poise
			var lan_hp := lan.combat_stats.health
			var ambient: Node2D = deer.effects._swarm
			if scenario == 0: await capture("ambient_%d" % side)
			deer.start_move(3,lan.position.x,scenario != 1)
			var pressed := false
			var reflected := false
			var prep_captured := false
			var flight_captured := false
			var completed := false
			var reflection_ticks := 0
			for f in 600:
				key(KEY_K,false)
				if not prep_captured and deer.age >= .6:
					prep_captured = true
					check((deer.red_warning_age() >= 0) == (scenario != 1),"Red chest cue precedes release; ordinary leaf stays ordinary")
					if scenario == 0: await capture("red_prep_%d" % side)
				if not flight_captured and deer.age >= 1.02:
					flight_captured = true
					if scenario == 0: await capture("red_out_%d" % side)
				if not pressed and scenario < 2 and deer.age >= DeerDuelBoss.LEAF_RELEASE:
					var gap := absf(deer.leaf_world_at(deer.age-DeerDuelBoss.LEAF_RELEASE).x-lan.position.x)
					if gap < 70:
						key(KEY_K,true)
						pressed = true
				await physics_frame
				if deer.leaf_reflected:
					reflection_ticks += 1
					if reflection_ticks == 12: await capture("red_return_%d" % side)
					if not reflected:
						reflected = true
						check(scenario == 0 and deer.attack_probes().is_empty(),"Manual red K changes the leaf to a harmless return projectile")
						check(deer.combat_stats.health == boss_hp and deer.combat_stats.poise == boss_poise,"Reflection grants no damage or poise before impact")
						check(lan.defense_state != LanPlayer.DefenseState.RED_PARRY_SUCCESS and not deer.red_parry_hold,"Reflection uses the shared parry without starting automatic melee cuts")
						var at := deer._reflected_world
						var fx_clock := deer.effects.clock
						deer.red_parry_hold = true
						for hold in 10: await physics_frame
						check(at == deer._reflected_world and fx_clock == deer.effects.clock,"Return flight and persistent leaves freeze together")
						deer.red_parry_hold = false
						await capture("red_reflect_%d" % side)
				if deer.opening > 0:
					completed = true
					if scenario == 0:
						check(reflected and reflection_ticks >= 5,"Leaf visibly travels back instead of awarding an instant remote hit")
						check(deer.combat_stats.health == boss_hp-DeerDuelBoss.REFLECT_DAMAGE,"Return impact applies exactly one health settlement")
						check(deer.combat_stats.poise == boss_poise-CombatTuning.BOSS_RED_PARRY_POISE,"Return impact applies exactly one red poise settlement")
						check(deer.opening >= DeerDuelBoss.REFLECT_OPENING-.05,"Full punish starts at return impact")
						await capture("red_impact_%d" % side)
					break
			check(completed,"Leaf sequence completes in both directions")
			check(is_instance_valid(ambient) and ambient == deer.effects._swarm,"One leaf population survives idle, windup, flight and recovery")
			if scenario < 2:
				check(contacts.count(CombatHitResult.Type.PARRY_SUCCESS) == 1 and lan.combat_stats.health == lan_hp,"Real K parries once without player damage")
			else:
				check(contacts.count(CombatHitResult.Type.NORMAL_HIT) == 1 and lan.combat_stats.health < lan_hp,"Undefended red leaf damages once across outbound and return")
			if scenario == 1:
				check(not reflected and deer.combat_stats.health == boss_hp,"Ordinary leaf K still destroys the blade without reflection damage")
			if scenario == 0:
				# Reach the deer on foot and land a real J within the impact opening.
				var hp_after_return := deer.combat_stats.health
				var struck := false
				for f in 240:
					key(KEY_J,false)
					var gap := deer.position.x-lan.position.x
					if not struck and absf(gap) > 155:
						Input.action_press(&"ui_left" if gap < 0 else &"ui_right")
					elif not struck:
						release_inputs()
						lan.facing_direction = signf(gap)
						key(KEY_J,true)
						struck = true
					await physics_frame
					if deer.combat_stats.health < hp_after_return: break
				print("REFLECT PUNISH side=",side," health=",hp_after_return,"->",deer.combat_stats.health," opening=",deer.opening," gap=",absf(deer.position.x-lan.position.x))
				check(struck and deer.combat_stats.health < hp_after_return and deer.opening > 0,"Real approach plus J fits after reflected impact")
				release_inputs()
	# Lifecycle and motion contracts below are stepped deterministically, not feel claims.
	reset_pair(-1)
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	deer.manual_control = true
	var front: Node2D = deer.effects._swarm
	var back: Node2D = deer.effects._ambient_back
	for f in 900: tick()
	check(is_instance_valid(front) and front == deer.effects._swarm and front.clock > 14,"Ambient leaves do not expire after the old eight-second tail")
	for i in 24:
		deer.start_move(i%4,lan.position.x)
		for f in 50: tick()
		deer._recover(1.25)
		for f in 40: tick()
	check(front == deer.effects._swarm and back == deer.effects._ambient_back and deer.effects._parts.size() == 2,"Repeated moves retain particle identity without accumulating effect nodes")
	for side in [-1,1]:
		reset_pair(side)
		deer.set_physics_process(false)
		deer.manual_control = false
		lan.set_physics_process(false)
		lan.position.x = deer.position.x+side*700
		deer.start_move(0,lan.position.x)
		check(absf(deer._destination-deer._origin.x) > 560,"Rush covers a greater fixed distance")
		var speed := absf(deer.rush_world_x(.16)-deer.rush_world_x(.15))/.01
		check(speed > 1000 and speed < 1100,"Rush reaches the intended burst speed after its short launch")
		lan.position.x = deer.position.x+side*440
		# Deliberately coarse ticks: the swept front must still touch a narrow body.
		for f in 40: deer._physics_process(.05)
		check(contacts.count(CombatHitResult.Type.NORMAL_HIT) == 1,"Fast swept rush cannot tunnel through the standing player")
	for cancel_kind in 4:
		reset_pair(-1)
		deer.set_physics_process(false)
		lan.set_physics_process(false)
		deer.manual_control = true
		deer.start_move(3,lan.position.x,true)
		for f in 70: tick()
		deer.on_attack_parried(deer.attack_hitbox.attack,lan.defense_contact_point(deer.global_position))
		check(deer.leaf_reflected,"Cleanup fixture has a real reflected projectile")
		match cancel_kind:
			0: deer.cancel_duel()
			1: deer.restart_duel()
			2: deer.combat_stats.apply_health_damage(deer.combat_stats.health)
			3: deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
		var hp := deer.combat_stats.health
		for f in 90: tick()
		check(not deer.leaf_reflected and deer.combat_stats.health == hp and deer.attack_probes().is_empty(),"Cancel/reset/death/poise break prevents late reflection damage %d" % cancel_kind)
		if cancel_kind in [0,2]: check(deer.effects._parts.is_empty(),"Teardown clears both ambient layers and attack art")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER DUEL REFLECTION AND AMBIENT")

func tick() -> void:
	deer._physics_process(1.0/60)
	if deer.move == &"": deer.wait_left = 999
	deer.vfx._process(1.0/60)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	paused = true
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
	paused = false

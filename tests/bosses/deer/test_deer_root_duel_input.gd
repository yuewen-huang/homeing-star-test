extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
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

func reset_pair(side := 1) -> void:
	release_inputs()
	room._combat_result = ""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.wait_left = 999
	deer.position.x = 360 if side>0 else 820
	lan.reset_after_map_fall(Vector2(800 if side>0 else 380,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	lan.facing_direction = -side
	contacts.clear()

func run() -> void:
	var quick := OS.get_cmdline_user_args().has("--combo-only")
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer = room.adapter.boss
	lan = room.player
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	# Actual walking over collision slopes in both directions, with no teleport aids.
	for layout in (0 if quick else 2):
		for side in [-1,1]:
			reset_pair(side)
			deer.manual_control = true
			var recipe := deer.terrain.plan(layout,640,deer.world_min_x,deer.world_max_x)
			deer.terrain.create_layout(layout,recipe,0)
			for f in 25: await physics_frame
			lan.reset_after_map_fall(Vector2(1100 if side<0 else 180,555))
			var lowest_y := 555.0
			var max_error := 0.0
			Input.action_press(&"ui_left" if side<0 else &"ui_right")
			for f in 420:
				await physics_frame
				lowest_y = minf(lowest_y,lan.position.y)
				max_error = maxf(max_error,absf(lan.position.y-deer.ground_y_at(lan.position.x)))
				if (side>0 and lan.position.x>1100) or (side<0 and lan.position.x<180): break
			release_inputs()
			print("ROOT WALK layout=",layout," side=",side," x=",lan.position.x," highest=",555-lowest_y," support_error=",max_error)
			check(lan.position.x>1100 if side>0 else lan.position.x<180,"Real input crosses the entire root layout in both directions")
			check(lowest_y < 502 and max_error<12,"Walking uses the raised collision tops without sinking or wall traps")
			check(lan.air_state != LanPlayer.AirState.WALL_SLIDING,"Root sides never turn into unintended wall-slide controls")
			# Stand on a platform, jump off, and regain ordinary grounded control.
			var mound: Dictionary = deer.terrain.roots[0]
			lan.reset_after_map_fall(Vector2(mound.x,deer.ground_y_at(mound.x)))
			for f in 5: await physics_frame
			key(KEY_W,true)
			Input.action_press(&"ui_right")
			var jumped := false
			for f in 140:
				await physics_frame
				jumped = jumped or lan.position.y < 555-mound.height-45
				if f == 80: key(KEY_W,false)
			release_inputs()
			check(jumped and lan.air_state == LanPlayer.AirState.GROUNDED,"Single jump leaves the root and lands with control restored")
	# Root warning allows an ordinary walk from the centre, or a single jump.
	for layout in (0 if quick else 2):
		for route in 2:
			reset_pair()
			deer.manual_control = false
			lan.reset_after_map_fall(Vector2(640,555))
			deer.start_root_rise(layout)
			lan.position.x = deer.terrain.roots[0].x
			var hp := lan.combat_stats.health
			var pressed := false
			for f in 240:
				if route==0 and deer.age>=.20 and not pressed:
					Input.action_press(&"ui_right")
					pressed = true
				elif route==1 and deer.age>=DeerRootDuelBoss.ROOT_PREP-.35 and not pressed:
					key(KEY_W,true)
					pressed = true
				await physics_frame
				if deer.opening>0: break
			release_inputs()
			print("ROOT DEFENSE layout=",layout," route=",route," hp=",hp,"->",lan.combat_stats.health," position=",lan.position)
			check(pressed and lan.combat_stats.health==hp,"Root eruption is avoidable with ordinary walking or a single jump")
			check(deer.opening>=1.15,"Root defense leads to the complete recovery window")
	# Full combined attack. Strike during the middle opening, then K or jump, then J.
	for side in [-1,1]:
		for route in 2:
			reset_pair(side)
			deer.manual_control = false
			deer.position.x = 640-side*440
			lan.reset_after_map_fall(Vector2(640,555))
			for f in 10: await physics_frame
			var lan_hp := lan.combat_stats.health
			var boss_hp := deer.combat_stats.health
			deer.start_drop_rush(lan.position.x)
			var mid_press := false
			var mid_hit := false
			var saw_rush := false
			var defended := false
			var final_press := false
			var completed := false
			var final_hp := 0
			var defense_captured := false
			for f in 1000:
				key(KEY_K,false)
				key(KEY_J,false)
				if deer.move == &"drop" and deer.age>.28 and deer.age<.90:
					Input.action_press(&"ui_left" if side<0 else &"ui_right")
				else:
					Input.action_release(&"ui_left")
					Input.action_release(&"ui_right")
				if deer.move == &"drop" and deer.opening>0 and not mid_press:
					lan.facing_direction = signf(deer.position.x-lan.position.x)
					key(KEY_J,true)
					mid_press = true
					await capture("root_combo_%d_%d_middle" % [side,route])
				if deer.move == &"drop" and deer.combat_stats.health < boss_hp: mid_hit = true
				# Choose the actual planned route after the middle hit: the flat lane
				# beyond the mound, or the raised takeoff, not the old flat-floor script.
				if mid_hit and not defended:
					var route_x: float = 640.0+side*(400 if route==0 else 70)
					var to: float = route_x-lan.position.x
					if absf(to)>8: Input.action_press(&"ui_left" if to<0 else &"ui_right")
				if deer.move == &"rush":
					saw_rush = true
					if not defended:
						if route == 0 and deer.age>=DeerDuelBoss.RUSH_PREP and absf(deer.position.x-lan.position.x)<295:
							lan.facing_direction = signf(deer.position.x-lan.position.x)
							key(KEY_K,true)
							defended = true
						elif route == 1 and deer.age >= .50:
							key(KEY_W,true)
							defended = true
					if deer.opening>0:
						if final_hp == 0: final_hp = deer.combat_stats.health
						var gap := deer.position.x-lan.position.x
						if not final_press and absf(gap)>150:
							Input.action_press(&"ui_left" if gap<0 else &"ui_right")
						elif not final_press and lan.air_state == LanPlayer.AirState.GROUNDED:
							release_inputs()
							lan.facing_direction = signf(gap)
							key(KEY_J,true)
							final_press = true
				await physics_frame
				if not defense_captured and deer.move == &"rush" and ((route==1 and deer.age>=.8) or (route==0 and contacts.has(CombatHitResult.Type.PARRY_SUCCESS))):
					defense_captured = true
					await capture("root_combo_%d_%d_defense" % [side,route])
				if final_hp>0 and deer.combat_stats.health<final_hp:
					completed = deer.opening>0
					break
				if saw_rush and deer.move == &"": break
			release_inputs()
			print("ROOT COMBO side=",side," route=",route," contacts=",contacts," player=",lan_hp,"->",lan.combat_stats.health," middle=",mid_hit," rush=",saw_rush," punish=",completed," position=",lan.position," deer=",deer.position," opening=",deer.opening)
			check(mid_hit,"Real J lands during the guaranteed middle opening")
			check(saw_rush and defended,"Combo reaches an announced rush after retreat")
			check(lan.combat_stats.health == lan_hp,"Real movement plus K/jump avoids both attacks")
			check(completed,"Real J lands inside the final punish window")
			if route==0: check(contacts.count(CombatHitResult.Type.PARRY_SUCCESS)==1,"Root-layout rush uses one ordinary K settlement")
	# Red leaf is visible over terrain and follows the real K return route on a mound.
	for side in ([] if quick else [-1,1]):
		reset_pair(side)
		deer.manual_control = true
		deer.position.x = 640-side*280
		deer.terrain.create_layout(0,deer.terrain.plan(0,640,deer.world_min_x,deer.world_max_x),0)
		for f in 25: await physics_frame
		lan.reset_after_map_fall(Vector2(640,deer.ground_y_at(640)))
		lan.facing_direction = -side
		deer.manual_control = false
		deer.start_move(3,lan.position.x,true)
		var lane := deer.leaf_launch_y()
		var hp := deer.combat_stats.health
		var lan_hp := lan.combat_stats.health
		var pressed := false
		var reflected := false
		for f in 360:
			key(KEY_K,false)
			if not pressed and deer.age>=DeerDuelBoss.LEAF_RELEASE and absf(deer.leaf_world_at(deer.age-DeerDuelBoss.LEAF_RELEASE).x-lan.position.x)<70:
				key(KEY_K,true)
				pressed = true
			await physics_frame
			if deer.leaf_reflected and not reflected:
				reflected = true
				await capture("root_red_return_%d" % side)
			if deer.opening>0: break
		check(lane<=deer.ground_y_at(640)-24 and is_equal_approx(lane,deer.leaf_launch_y()),"Leaf lane clears the root and stays fixed after the cue")
		check(reflected and contacts.count(CombatHitResult.Type.PARRY_SUCCESS)==1 and lan.combat_stats.health==lan_hp,"Real K reflects the red leaf from a raised platform")
		check(deer.combat_stats.health==hp-DeerDuelBoss.REFLECT_DAMAGE and deer.opening>=2.2,"Terrain red return applies one hit and the full punish window")
		release_inputs()
	# Autonomous stage uses all five families, changes layouts, and remains phase two.
	reset_pair()
	assist.set_player_invincible(true)
	deer._rng.seed = 808
	deer.wait_left = .1
	var seen: Array[StringName] = []
	var layouts := {}
	deer.move_started.connect(func(id: StringName): seen.append(id))
	for f in (0 if quick else 6000):
		await physics_frame
		if deer.terrain.layout>=0: layouts[deer.terrain.layout]=true
		if seen.size()>=20: break
	if not quick:
		print("ROOT AI ORDER ",seen," layouts=",layouts)
		check(seen.size()>=20,"Autonomous phase keeps selecting through terrain retirements")
		for id in DeerRootDuelBoss.ROOT_MOVES: check(seen.has(id),"Autonomous phase uses "+String(id))
		check(layouts.size()==2 and deer.phase==2,"Both layouts appear without enabling later phases")
	release_inputs()
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER ROOT DUEL REAL INPUT")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	paused = true
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
	paused = false

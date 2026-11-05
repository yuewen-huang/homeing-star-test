extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var contacts: Array[Dictionary] = []
var order: Array[StringName] = []
var groups: Array[StringName] = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_W,KEY_J,KEY_L]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func reset_pair(side: int) -> void:
	release()
	room._combat_result = ""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.wait_left = 999
	deer.position = Vector2(820 if side<0 else 360,555)
	lan.reset_after_map_fall(Vector2(380 if side<0 else 800,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	lan.facing_direction = -side
	contacts.clear()
	order.clear()
	groups.clear()

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	var slot := -1
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): slot=i
	check(slot>=0,"Vine phrase is selectable in the shared room")
	room.select_boss(slot)
	await process_frame
	deer = room.adapter.boss
	lan = room.player
	check(deer.manual_control and not room.combat_simulation,"Room selection remains safe and manual by default")
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append({"move":deer.move,"result":result,"opening":deer.opening,"x":lan.position.x}))
	deer.move_started.connect(func(id):
		order.append(id)
		groups.append(deer.get_parry_chain_key()))
	for difficulty in [BattleAssistSettingsService.Difficulty.HARD,BattleAssistSettingsService.Difficulty.NORMAL]:
		assist.set_difficulty(difficulty)
		for side in [-1,1]:
			for far in [false,true]:
				reset_pair(side)
				for f in 12: await physics_frame
				deer.start_phrase()
				var rush_k := false
				var sweep_k := false
				var jumped := false
				var punished := false
				var saw_end := false
				var grounded_at_sweep := false
				var landing_x := NAN
				var saw_air := false
				var initial_hp := lan.combat_stats.health
				var boss_hp: int = deer.combat_stats.health
				var jump_at: float = deer.VINE_RELEASE-(.23 if difficulty==BattleAssistSettingsService.Difficulty.HARD else .07)
				var sweep_lock := Vector2.INF
				var sweep_position_locked := true
				var captured_warning := false
				var captured_jump := false
				for f in 700:
					for code in [KEY_K,KEY_J]: key(code,false)
					Input.action_release(&"ui_left")
					Input.action_release(&"ui_right")
					if deer.move==&"rush" and not rush_k and deer.age>=.68 and absf(deer.position.x-lan.position.x)<295:
						key(KEY_K,true)
						rush_k = true
					if deer.move==&"vine_return":
						if not jumped and deer.age>=jump_at:
							key(KEY_W,true)
							jumped = true
						if jumped and difficulty==BattleAssistSettingsService.Difficulty.NORMAL and deer.age>jump_at+.16:
							key(KEY_W,false)
						if far and deer.age>.14:
							Input.action_press(&"ui_right" if side<0 else &"ui_left")
						if not captured_warning and deer.age>deer.VINE_RELEASE-.15:
							captured_warning = true
							if side==1 and not far: await capture("vine_warning_%d" % difficulty)
						if not captured_jump and deer.age>deer.VINE_RELEASE+.13:
							captured_jump = true
							if side==1 and not far: await capture("vine_jump_%d" % difficulty)
					if jumped and lan.air_state!=LanPlayer.AirState.GROUNDED: saw_air=true
					if saw_air and is_nan(landing_x) and lan.air_state==LanPlayer.AirState.GROUNDED: landing_x=lan.position.x
					if deer.move==&"sweep" and deer.opening<=0:
						if sweep_lock==Vector2.INF: sweep_lock=Vector2(deer.position.x,deer.direction)
						else: sweep_position_locked = sweep_position_locked and sweep_lock==Vector2(deer.position.x,deer.direction)
					if deer.move==&"sweep" and deer.age>=.48 and not sweep_k:
						key(KEY_W,false)
						grounded_at_sweep = lan.air_state==LanPlayer.AirState.GROUNDED
						key(KEY_K,true)
						sweep_k = true
					if deer.opening>0:
						saw_end = true
						if not punished:
							var gap: float = deer.position.x-lan.position.x
							if absf(gap)>140: Input.action_press(&"ui_right" if gap>0 else &"ui_left")
							elif lan.air_state==LanPlayer.AirState.GROUNDED:
								lan.facing_direction = signf(gap)
								key(KEY_J,true)
								punished = true
					await physics_frame
					if saw_end and deer.opening<=0:
						deer.wait_left = 999
						break
				release()
				print("VINE ROUTE side=",side," far=",far," difficulty=",difficulty," HP=",lan.combat_stats.health," landing=",landing_x," boss_damage=",boss_hp-deer.combat_stats.health," contacts=",contacts)
				check(order==[&"rush",&"vine_return",&"sweep"],"Exactly the requested three moves run, without fallback drops")
				check(groups.size()==3 and groups[0]==groups[1] and groups[1]==groups[2],"Ordinary difficulty retains one assist group across the phrase")
				check(contacts.any(func(c): return c.move==&"rush" and c.result==CombatHitResult.Type.PARRY_SUCCESS and c.opening==0),"Real rush K continues without a free recovery")
				check(jumped and lan.combat_stats.health==initial_hp,"Real single jump and chosen landing avoid the full phrase")
				check(grounded_at_sweep,"Fixed follow-up leaves time to land before ground K")
				check(sweep_position_locked,"Sweep cue commits position and direction without chasing the landing")
				check(saw_air and not is_nan(landing_x),"A real airborne arc lands, including the short held jump route")
				if not far:
					check(contacts.any(func(c): return c.move==&"sweep" and c.result==CombatHitResult.Type.PARRY_SUCCESS and c.opening==0),"Near landing permits a real second K while preserving the full sweep")
				check(saw_end and deer.combat_stats.health<boss_hp,"Real J reaches the final recovery from this landing")
	# Stay grounded: the golden moving crest actually damages, exactly once.
	reset_pair(-1)
	deer.set_physics_process(false)
	deer.position.x=270
	deer.vine_far=820
	deer._rush_facing=-1
	deer.pressure.start()
	deer.pressure.step=1
	deer.start_vine_return()
	lan.set_physics_process(false)
	var hp := lan.combat_stats.health
	var release_frame := ceili(deer.VINE_RELEASE*60)
	var end_frame := ceili((deer.VINE_RELEASE+deer.VINE_TRAVEL)*60)
	for f in release_frame:
		deer.age=f/60.0
		deer._duel_vine_return()
	check(lan.combat_stats.health==hp and deer.vine.probes().is_empty(),"Slack and full gold warning never deal damage")
	for f in range(release_frame,end_frame):
		deer.age=f/60.0
		deer._duel_vine_return()
	check(lan.combat_stats.health<hp and contacts.size()==1,"Grounded failure takes one real gold crest hit, never repeated segments")
	check(contacts[0].result!=CombatHitResult.Type.PARRY_SUCCESS,"Low return is not a normal-parry contact")
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise)
	check(deer.poise_broken and not deer.pressure.active and deer.vine.points.is_empty(),"True poise break cancels the queued sweep and clears vine for reward")
	check(deer.stagger_remaining>=4.9,"Five-second break release remains intact")
	deer.restart_duel()
	deer.set_physics_process(false)
	check(deer.vine.points.is_empty() and not deer.pressure.active,"Retry clears the owned vine and phrase")
	var old: WeakRef = weakref(deer.vine)
	room.select_boss(0)
	await process_frame
	check(old.get_ref()==null,"Switching frees the entire vine subtree")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE PHRASE")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

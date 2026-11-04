extends "../tests/support/harness.gd"
## Scripted observations, not a claim of human difficulty or fun.
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
var samples: Array[Dictionary] = []
var contacts := {}
var attacks := {}
var break_times: Array[Dictionary] = []
var phase_hp_before := 0
var normal_damage := 0
var break_damage := 0
var elapsed := 0.0
var active_capture := false
var player_defeats := 0
var root_phase := false

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_L,KEY_J,KEY_E]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func health_changed(hp: int, _max: int) -> void:
	if active_capture and hp < phase_hp_before:
		if deer.poise_broken: break_damage += phase_hp_before-hp
		else: normal_damage += phase_hp_before-hp
	phase_hp_before=hp

func run() -> void:
	root_phase=OS.get_cmdline_user_args().has("--root-phase")
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd" if root_phase else "deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_combat_simulation(true)
	deer=room.adapter.boss
	lan=room.player
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	deer.move_started.connect(func(id): attacks[String(id)]=int(attacks.get(String(id),0))+1)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts[str(result)]=int(contacts.get(str(result),0))+1)
	deer.combat_stats.health_changed.connect(health_changed)
	lan.combat_stats.health_depleted.connect(func():
		if active_capture: player_defeats+=1)
	deer.combat_stats.poise_depleted.connect(func(): break_times.append({"seconds":elapsed,"completed_phrases":deer.pressure.completed,"hp":deer.combat_stats.health}))
	for policy in (["no_input","fixed_defense","defend_and_punish"] if root_phase else ["no_input","defend_and_punish"]):
		active_capture=false
		release()
		room._combat_result=""
		lan.set_input_frozen(false)
		lan.reset_after_map_fall(Vector2(500,555))
		lan.combat_stats.restore_health()
		lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
		lan.parry_chain.cancel()
		deer.restart_duel()
		deer._rng.seed=20261104
		contacts={}
		attacks={}
		break_times=[]
		normal_damage=0
		break_damage=0
		player_defeats=0
		phase_hp_before=deer.combat_stats.health
		active_capture=true
		var recover_frames:=0
		var transition_frames:=0
		var captured:=0
		var parried_serial:=-1
		var dodged_serial:=-1
		var leaf_pressed:={}
		var last_attack_frame:=-99
		var last_e_frame:=-99
		var min_hp:=100
		var occupation_samples:=0
		var below_samples:=0
		var tactics:={}
		var claim_escapes:=0
		var last_claim:=-1
		var was_in_claim:=false
		var terrain_samples: Array[Dictionary]=[]
		var frames:=1800 if policy=="no_input" else 5400
		for frame in frames:
			elapsed=frame/60.0
			release()
			if policy=="fixed_defense" and frame%28==0: key(KEY_K,true)
			if policy=="defend_and_punish":
				var gap: float=deer.position.x-lan.position.x
				var gold := deer.move==&"drop" and deer.opening<=0 and deer.age>.38 and deer.age<1.20
				var escape_claim:=false
				var escape_side:=0
				if root_phase and deer.summit_claim.running:
					var zone: Rect2=deer.summit_claim.footprint()
					escape_claim=lan.position.x>zone.position.x-35 and lan.position.x<zone.end.x+35
					escape_side=1 if zone.get_center().x<640 else -1
				if escape_claim:
					Input.action_press(&"ui_right" if escape_side>0 else &"ui_left")
					if deer.summit_claim.clock>.70 and frame%25==0: key(KEY_L,true)
				elif root_phase and (lan.position.x<220 or lan.position.x>1060):
					Input.action_press(&"ui_right" if lan.position.x<640 else &"ui_left")
				elif gold and absf(lan.position.x-deer._aim)<120:
					var side := 1 if lan.position.x<640 else -1
					Input.action_press(&"ui_right" if side>0 else &"ui_left")
					if deer.age>=.86 and absf(lan.position.x-deer._aim)<100 and dodged_serial!=deer._duel_serial:
						key(KEY_L,true)
						dodged_serial=deer._duel_serial
				else:
					var defend:=false
					if deer._duel_serial!=parried_serial and deer.opening<=0:
						defend=(deer.move==&"rush" and deer.age>=.68 and absf(gap)<295) or (deer.move==&"sweep" and deer.age>=.48 and deer.age<.8 and absf(gap)<290)
						if defend: parried_serial=deer._duel_serial
					for leaf in deer.pressure.projectiles.duplicate():
						if not is_instance_valid(leaf) or leaf.finished or leaf.leaf_reflected or leaf_pressed.has(leaf.serial): continue
						if leaf.world_at(leaf.flight).distance_to(lan.global_position+Vector2(0,-35))<75:
							defend=true
							leaf_pressed[leaf.serial]=true
					if defend: key(KEY_K,true)
					else:
						var opportunity := deer.opening>0 or deer.move==&"" or deer.poise_broken
						if opportunity:
							if absf(gap)>120: Input.action_press(&"ui_right" if gap>0 else &"ui_left")
							if absf(gap)<180:
								lan.facing_direction=1 if gap>0 else -1
								if deer.poise_broken and deer.break_empower_available and lan.find_throw_target()==deer:
									if frame-last_e_frame>=10: key(KEY_E,true); last_e_frame=frame
								elif frame-last_attack_frame>=12: key(KEY_J,true); last_attack_frame=frame
			await physics_frame
			if root_phase:
				if frame%120==0 and frame<=600:
					terrain_samples.append({"seconds":elapsed,"player":str(lan.position),"boss":str(deer.position),"support":deer.ground_y_at(lan.position.x),"snap":lan.resolve_ground_snap_y(),"terrain_age":deer.terrain.age,"progress":deer.terrain.roots[0].progress if not deer.terrain.roots.is_empty() else -1,"air":lan.air_state})
				tactics[String(deer.pressure.tactic)]=true
				if lan.position.y>430: below_samples+=1
				if deer.summit_claim.running:
					occupation_samples+=1
					var zone: Rect2=deer.summit_claim.footprint()
					var inside:=lan.position.x>zone.position.x and lan.position.x<zone.end.x
					if last_claim!=deer.summit_claim.serial:
						last_claim=deer.summit_claim.serial
						was_in_claim=inside
					elif was_in_claim and not inside:
						claim_escapes+=1
						was_in_claim=false
			if deer.opening>0: recover_frames+=1
			elif deer.move==&"": transition_frames+=1
			min_hp=mini(min_hp,lan.combat_stats.health)
			if DisplayServer.get_name()!="headless" and captured<5 and frame in [90,200,320,470,640]:
				await capture("%s_%03d" % [policy,frame])
				captured+=1
			if deer._stopped: break
		release()
		active_capture=false
		var denominator := maxf(1,(elapsed+1.0/60)*60)
		var row := {"policy":policy,"difficulty":"normal","seconds":elapsed+1.0/60,"moves":attacks.duplicate(),"contacts":contacts.duplicate(),"player_minimum_hp":min_hp,"boss_remaining_hp":deer.combat_stats.health,"boss_defeated":deer._stopped,"completed_phrases":deer.pressure.completed,"breaks":break_times.duplicate(true),"normal_damage":normal_damage,"break_damage":break_damage,"recovery_percent":recover_frames/denominator*100,"transition_percent":transition_frames/denominator*100}
		samples.append(row)
		row["player_defeats_before_practice_refill"]=player_defeats
		if root_phase:
			row["root_tactics"]=tactics.keys()
			row["occupation_seconds"]=occupation_samples/60.0
			row["claim_escapes"]=claim_escapes
			row["below_platform_seconds"]=below_samples/60.0
			row["terrain_samples"]=terrain_samples
		print("PRESSURE_FIGHT "+JSON.stringify(row))
	var file:=FileAccess.open(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("pressure_fight_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"\t"))
	file.close()
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER PRESSURE FIGHT MEASUREMENTS")

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

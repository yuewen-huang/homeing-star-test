extends "test_deer_wind_overlap_routes.gd"
## Real-input acceptance for the fourth-phase escape handoff. Reuses the real
## forest/rematch fixture, with ordinary health and the production spell code.
var suite_results: Array = []
const PlayerAttackEffect = preload("res://scripts/player/lan/lan_attack_effect.gd")
var confirmed_player_hit := -1.0
var counter_input_active := false

func release() -> void:
	super.release()
	key(KEY_J,false)
	key(KEY_I,false)

func stamp(kind: String, data := {}) -> void:
	var entry: Dictionary=data.duplicate()
	entry.merge({"event":kind,"wall":snappedf(wall,.001),"action":snappedf(deer._time-route_start,.001),
		"hp":lan.combat_stats.health,"x":snappedf(lan.position.x,.1),"y":snappedf(lan.position.y,.1)})
	events.append(entry)
	print("WIND_ESCAPE_EVENT "+JSON.stringify(entry))

func escape_opening() -> bool:
	return deer.has_method("escape_opening_active") and deer.escape_opening_active()

func track_player_effect(node: Node) -> void:
	if not (node is PlayerAttackEffect or node is LanSwordWaveProjectile): return
	node.hit_landed.connect(func(target: DamageReceiver2D):
		if counter_input_active and is_instance_valid(deer) and target==deer:
			confirmed_player_hit=wall
			stamp("real_player_hit",{"source":node.get_class()}))

func parry_visible_leaves(spell: Node2D, noticed: Dictionary, pressed: Dictionary) -> void:
	for obj in spell.objects:
		if obj.dead or obj.reflected or spell.age<obj.born: continue
		var relative: Vector2=lan.position+Vector2(0,-35)-obj.at
		var velocity: Vector2=obj.velocity
		var ahead: float=relative.dot(velocity)/velocity.length_squared()
		var miss: float=(relative-velocity*maxf(ahead,0)).length()
		var id: String="%d_%d"%[obj.contact.get_instance_id(),obj.bounces]
		if ahead>0 and ahead<.45 and miss<65 and not noticed.has(id): noticed[id]=wall
		if noticed.has(id) and wall-float(noticed[id])>=.15 and ahead>=-.02 and ahead<.20 and miss<65 and not pressed.has(id):
			key(KEY_K,true)
			pressed[id]=true
			stamp("K_leaf",{"ahead":ahead,"visible_for":wall-float(noticed[id])})

func visible_meteor_step(spell: Node2D, roots_gone: bool, pressed: Dictionary) -> void:
	for obj in spell.objects:
		var local: float=spell.age-obj.born
		if local<.15 or local>1.0: continue
		if absf(lan.position.x-obj.x)>=132: continue
		var side: float=signf(lan.position.x-obj.x)
		if is_zero_approx(side): side=-1
		var target_x: float=lan.position.x+side*90
		if not roots_gone and (target_x<1150 or target_x>1410): side=-side
		if roots_gone and (target_x<lan.world_min_x+35 or target_x>lan.world_max_x-35): side=-side
		Input.action_release(&"ui_right")
		Input.action_release(&"ui_left")
		Input.action_press(&"ui_right" if side>0 else &"ui_left")
		var id := "late_meteor_%s"%obj.born
		if roots_gone and local>=.74 and local<.84 and absf(lan.position.x-obj.x)<105 and not pressed.has(id):
			Input.action_release(&"ui_right")
			Input.action_release(&"ui_left")
			key(KEY_K,false)
			key(KEY_D,side>0)
			key(KEY_A,side<0)
			key(KEY_L,true)
			pressed[id]=true
			stamp("L_late_meteor",{"visible_for":local,"x":obj.x})
		return

func acceptance_route(offset: float, delay: float, overlap: bool, counter: String,
		mode := "normal", difficulty := BattleAssistSettingsService.Difficulty.HARD, movement := "adaptive") -> Dictionary:
	setup_route()
	confirmed_player_hit=-1.0
	counter_input_active=false
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)
	var escape_side := signf(offset) if not is_zero_approx(offset) else 1.0
	deer.position.x=1280+escape_side*380
	lan.reset_after_map_fall(Vector2(1280+offset,555))
	var start_x: float=lan.position.x
	var order: Array=[1,0,2] if overlap else [1]
	var next := 0
	var times := [0.0,1.9,4.4]
	var roots_at := -1.0
	var roots_action := -1.0
	var input_at := -1.0
	var teleport_at := -1.0
	var opening_at := -1.0
	var opening_end := -1.0
	var hit_at := -1.0
	var new_cast_at := -1.0
	var boss_hp_at_counter := -1
	var counter_started := false
	var counter_pressed := false
	var latest_hp := 100
	var legal := true
	var peak_slots := 0
	var peak_spells := 0
	var gap_at_opening := -1.0
	var meteor_count := 0
	var hp_at_teleport := -1
	var hp_at_opening := -1
	var hp_at_opening_end := -1
	var safe_opening := true
	var last_threat_at := -1.0
	var meteor_births: Array[float] = []
	var meteor_interval := 0.0
	var late_teleport := false
	var noticed := {}
	var pressed := {}
	var tornado: Node2D
	route_name="%s_%+d_%dms_%s_%s_%d_%s"%["overlap" if overlap else "solo",int(offset),roundi(delay*1000),counter,mode,difficulty,movement]
	for frame in 1500:
		release()
		var action: float=deer._time-route_start
		# This fixes the three legal choices during the exchange. Once the real
		# escape recovery begins, its own countdown and the real AI resume.
		if opening_at<0: deer.wait_left=999
		if next<order.size() and action>=times[next] and deer.cast_index<0 and deer.opening<=0:
			var index: int=order[next]
			legal=legal and deer.can_schedule_spell(index) and index!=deer.previous
			if deer.can_schedule_spell(index):
				deer.start_spell(index)
				stamp("cast",{"spell":deer.SPELLS[index]})
				next+=1
		peak_slots=maxi(peak_slots,deer.active_spell_slots())
		peak_spells=maxi(peak_spells,deer.spells.size())
		monitor_contacts()
		if overlap and teleport_at>=0 and opening_at<0:
			Input.action_press(&"ui_left" if escape_side>0 else &"ui_right")
		var future_threats := 0
		for spell in deer.spells:
			if not is_instance_valid(spell): continue
			if spell.has_pending_threat(): future_threats+=1
			if spell.kind=="meteors":
				meteor_count=maxi(meteor_count,spell.spawned)
				meteor_interval=float(spell.config.interval)
				while meteor_births.size()<spell.objects.size():
					meteor_births.append(float(spell.objects[meteor_births.size()].born))
					stamp("meteor_born",{"index":meteor_births.size(),"spell_age":meteor_births.back()})
			if spell.kind=="tornado":
				tornado=spell
				if spell.roots_released and roots_at<0:
					roots_at=wall
					roots_action=action
					var visible_roots: int=spell.objects.filter(func(obj): return obj.type=="root" and obj.sprite.visible).size()
					check(visible_roots==0,"Visible roots disappear on the escape cue: "+route_name)
					stamp("roots_gone",{"spell_age":spell.age,"offset":lan.position.x-1280})
					await snap("roots_gone")
			if spell.kind=="leaves" and (input_at<0 or teleport_at>=0): parry_visible_leaves(spell,noticed,pressed)
			if spell.kind=="meteors" and (roots_at<0 or teleport_at>=0) and opening_at<0:
				if teleport_at<0 or movement=="adaptive": visible_meteor_step(spell,roots_at>=0,pressed)
				elif movement=="first_roll_walk" and not spell.objects.is_empty() and not pressed.has("first_roll"):
					var visible_for: float=spell.age-float(spell.objects[0].born)
					if visible_for>=.74:
						key(KEY_K,false)
						key(KEY_A,escape_side>0)
						key(KEY_D,escape_side<0)
						key(KEY_L,true)
						pressed["first_roll"]=true
						stamp("L_first_meteor",{"visible_for":visible_for})
		if future_threats>0 and opening_at<0: last_threat_at=wall
		var should_press := roots_at>=0 and wall-roots_at+0.00001>=delay
		if mode=="early": should_press=is_instance_valid(tornado) and tornado.has_method("root_clear_time") and tornado.age>=tornado.root_clear_time()-.65
		if input_at<0 and should_press:
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
			key(KEY_K,false)
			key(KEY_D,escape_side>0)
			key(KEY_A,escape_side<0)
			key(KEY_U,true)
			input_at=wall
			stamp("U",{"from_roots":wall-roots_at if roots_at>=0 else -1,"air":lan.air_state,"attack":lan.attack_state})
		if teleport_at<0 and input_at>=0 and absf(lan.position.x-start_x)>350:
			teleport_at=wall
			hp_at_teleport=lan.combat_stats.health
			late_teleport=roots_at<0
			stamp("teleport",{"from_input":wall-input_at})
			await snap("escaped")
		if opening_at<0 and escape_opening():
			opening_at=wall
			hp_at_opening=lan.combat_stats.health
			gap_at_opening=absf(deer.position.x-lan.position.x)
			stamp("opening",{"duration":deer.opening,"gap":gap_at_opening,"remaining_spells":deer.spells.size()})
			await snap("opening")
		if opening_at>=0:
			if escape_opening():
				safe_opening=safe_opening and future_threats==0 and deer.cast_index<0 and lan.combat_stats.health==hp_at_opening
			if opening_end<0 and not escape_opening():
				opening_end=wall
				hp_at_opening_end=lan.combat_stats.health
				stamp("opening_ended")
			if new_cast_at<0 and deer.cast_index>=0:
				new_cast_at=wall
				stamp("next_cast",{"spell":deer.SPELLS[deer.cast_index]})
			# Give the authored low-staff pose a visible reaction interval before
			# moving toward the boss or starting a real counterattack.
			if teleport_at>=0 and wall-opening_at>=.20 and mode=="normal" and counter!="none" and not counter_pressed:
				var direction: float=signf(deer.position.x-lan.position.x)
				var gap: float=absf(deer.position.x-lan.position.x)
				var reach := 130.0 if counter=="J" else 520.0
				if not counter_started:
					boss_hp_at_counter=deer.combat_stats.health
					counter_started=true
				if gap>reach:
					Input.action_press(&"ui_right" if direction>0 else &"ui_left")
				elif lan.attack_state==LanPlayer.AttackState.NONE and lan.ground_action_state==LanPlayer.GroundActionState.NONE:
					key(KEY_D,direction>0)
					key(KEY_A,direction<0)
					key(KEY_J if counter=="J" else KEY_I,true)
					counter_pressed=true
					counter_input_active=true
					stamp(counter,{"gap":gap,"opening_left":deer.opening})
			if counter_started and hit_at<0 and confirmed_player_hit>=opening_at and deer.combat_stats.health<boss_hp_at_counter:
				hit_at=wall
				stamp("counter_hit",{"damage":boss_hp_at_counter-deer.combat_stats.health,"opening_left":deer.opening})
				await snap("counter_hit")
		if lan.combat_stats.health<latest_hp:
			stamp("health_loss",{"damage":latest_hp-lan.combat_stats.health})
			latest_hp=lan.combat_stats.health
			await snap("damage")
		if latest_hp<=28: break
		if mode!="normal" and latest_hp<100: break
		if new_cast_at>=0 and wall-new_cast_at>.2: break
		if opening_end>=0 and wall-opening_end>2: break
		await physics_frame
		wall+=1.0/60.0
	release()
	var result := {"route":route_name,"legal":legal,"casts":next,"expected_casts":order.size(),"hp":lan.combat_stats.health,
		"roots_at":roots_at,"roots_action":roots_action,"u_at":input_at,"teleport_at":teleport_at,"opening_at":opening_at,
		"opening_end":opening_end,"hit_at":hit_at,"next_cast_at":new_cast_at,"gap_at_opening":gap_at_opening,
		"peak_non_leaf":peak_slots,"peak_spells":peak_spells,"meteor_count":meteor_count,"meteor_births":meteor_births,
		"hp_at_teleport":hp_at_teleport,"hp_at_opening":hp_at_opening,"hp_at_opening_end":hp_at_opening_end,
		"safe_opening":safe_opening,"last_threat_at":last_threat_at,"movement":movement,
		"teleported_before_roots":late_teleport,"events":events.duplicate(true)}
	suite_results.append(result)
	print("WIND_ESCAPE_RESULT "+JSON.stringify(result))
	check(legal and peak_slots<=2 and next==order.size(),"Legal complete spell schedule: "+route_name)
	if mode=="normal":
		check(roots_at>=0 and teleport_at>=input_at and input_at>=roots_at+delay-.001,"Real U follows the visible cue and reaction delay: "+route_name)
		check(hp_at_teleport==100,"Visible-root cue plus delayed U escapes unharmed: "+route_name)
		if not overlap or offset<0 or movement!="adaptive":
			check(lan.combat_stats.health==100,"Complete defense and counter route stays unharmed: "+route_name)
		check(opening_at>=0 and opening_end>opening_at,"Distinct natural recovery opens and ends: "+route_name)
		check(safe_opening and opening_at>last_threat_at and hp_at_opening_end==hp_at_opening,"Recovery has no future threats, new casts or residual damage: "+route_name)
		check(new_cast_at>=opening_end and new_cast_at>=0,"Autonomous follow-up resumes only after recovery: "+route_name)
		if overlap:
			check(peak_spells>=3 and meteor_count==7,"Three-spell pressure and all seven meteors are retained: "+route_name)
			var separated := meteor_births.size()==7
			for i in range(1,meteor_births.size()):
				separated=separated and meteor_births[i]-meteor_births[i-1]>=meteor_interval-.001
			check(separated,"All seven actual meteor births retain separated cadence: "+route_name)
		if counter!="none": check(hit_at>=0 and opening_at>=0 and hit_at>=opening_at and (opening_end<0 or hit_at<opening_end),"Real "+counter+" reaches before recovery ends: "+route_name)
	else:
		check(lan.combat_stats.health<100,"Mistimed U retains real consequences: "+route_name)
	room.encounter.stop()
	await wait_frames(2)
	return result

func run() -> void:
	var save := use_memory_progress()
	node_added.connect(track_player_effect)
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	(root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested=true
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	check(room.player.combat_stats.max_health==100 and not room.player.combat_stats.refill_health_on_depletion,"Ordinary production player, 100 HP, no lethal refill")
	if "--right-walk-only" in OS.get_cmdline_user_args():
		await acceptance_route(80,.25,true,"J","normal",BattleAssistSettingsService.Difficulty.HARD,"walk")
	elif "--right-roll-walk-only" in OS.get_cmdline_user_args():
		await acceptance_route(80,.25,true,"J","normal",BattleAssistSettingsService.Difficulty.HARD,"first_roll_walk")
	elif "--overlap-only" in OS.get_cmdline_user_args():
		await acceptance_route(0,.20,true,"J")
		await acceptance_route(80,.25,true,"J")
		await acceptance_route(-80,.25,true,"I","normal",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	elif "--review" in OS.get_cmdline_user_args():
		await acceptance_route(80,.25,true,"J")
		await acceptance_route(-80,.25,true,"I","normal",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	else:
		await acceptance_route(0,.20,false,"J")
		await acceptance_route(80,.25,false,"J")
		await acceptance_route(-80,.25,false,"I")
		await acceptance_route(0,.20,true,"J")
		await acceptance_route(80,.25,true,"J")
		await acceptance_route(-80,.25,true,"I","normal",BattleAssistSettingsService.Difficulty.NIGHTMARE)
		await acceptance_route(0,0.0,false,"none","early")
		await acceptance_route(0,.65,false,"none","late")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("escape_routes.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(suite_results,"\t"))
	room.encounter.stop()
	current_scene=null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER WIND ESCAPE READABILITY")

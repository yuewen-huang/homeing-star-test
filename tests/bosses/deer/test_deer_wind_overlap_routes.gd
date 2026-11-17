extends "../../support/harness.gd"
## Investigation only. Production room, ordinary 100 HP player, legal scripted
## spell choices and real input. No damage, collision or ability overrides.
var room: Chapter1DeerBossRoom
var deer: Node2D
var lan: LanPlayer
var output := ""
var wall := 0.0
var route_start := 0.0
var events: Array = []
var reports: Array = []
var connected := {}
var route_name := ""

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_L,KEY_U,KEY_W,KEY_A,KEY_D]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func stamp(kind: String, data := {}) -> void:
	var entry: Dictionary=data.duplicate()
	entry.merge({"event":kind,"wall":snappedf(wall,.001),"action":snappedf(deer._time-route_start,.001),
		"hp":lan.combat_stats.health,"x":snappedf(lan.position.x,.1),"y":snappedf(lan.position.y,.1)})
	events.append(entry)
	print("WIND_OVERLAP_EVENT "+JSON.stringify(entry))

func snap(label: String) -> void:
	if DisplayServer.get_name()=="headless" or output.is_empty(): return
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(route_name+"_"+label+".png"))

func monitor_contacts() -> void:
	for spell in deer.spells:
		if not is_instance_valid(spell): continue
		for contact in spell.contacts:
			if not is_instance_valid(contact) or connected.has(contact.get_instance_id()): continue
			connected[contact.get_instance_id()]=true
			var hitbox: CombatHitbox2D=contact.hitbox
			hitbox.hit_resolved.connect(func(_target,result):
				stamp("contact",{"spell":spell.kind if is_instance_valid(spell) else "retired","result":result,
					"attack":String(hitbox.attack.attack_id) if is_instance_valid(hitbox) and hitbox.attack!=null else "retired"}))

func setup_route() -> void:
	release()
	room.encounter.stop()
	room.encounter._spawn_phase(4,900)
	deer=room.deer
	deer.transform_left=0
	deer.invulnerable=false
	deer.wait_left=999
	deer._rng.seed=20261117
	deer.selected_exercise=-1
	lan=room.player
	lan.reset_after_map_fall(Vector2(1280,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.instant_dash_cooldown_remaining=0
	lan.parry_chain.cancel()
	room.encounter.start()
	room._process(0)
	wall=0
	route_start=deer._time
	events=[]
	connected={}

func route(order: Array, delay: float, strategy: String, difficulty: int) -> void:
	setup_route()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(difficulty)
	route_name="%s_%s_%dms_%d"%["core" if order.has(4) else "meteors" if order.has(2) else "tornado",strategy,roundi(delay*1000),difficulty]
	var next := 0
	var scheduled := [0.0,1.9,4.4]
	var roots_at := -1.0
	var teleported_at := -1.0
	var input_at := -1.0
	var initial_x := lan.position.x
	var sent := {}
	var threats := {}
	var max_slots := 0
	var peak_live := 0
	var legal := true
	var last_hp := 100
	var selected_side := 1.0
	var all_casts := false
	var first_damage := -1.0
	var first_jump := -1.0
	for f in 1200:
		release()
		# This only suppresses random selection, preserving the production movement,
		# cast duration, .62 recovery and minimum .24/.28 inter-cast waits below.
		deer.wait_left=999
		var action: float=deer._time-route_start
		if next<order.size() and action>=scheduled[next] and deer.cast_index<0 and deer.opening<=0:
			var index: int=order[next]
			legal=legal and deer.can_schedule_spell(index) and index!=deer.previous
			if deer.can_schedule_spell(index):
				deer.start_spell(index)
				stamp("cast",{"spell":deer.SPELLS[index],"slots":deer.active_spell_slots()})
				next+=1
		max_slots=maxi(max_slots,deer.active_spell_slots())
		peak_live=maxi(peak_live,deer.spells.size())
		monitor_contacts()
		for spell in deer.spells:
			if not is_instance_valid(spell): continue
			if spell.kind=="tornado" and spell.roots_released and roots_at<0:
				roots_at=wall
				stamp("roots_gone",{"spell_age":spell.age})
				await snap("roots_gone")
			if spell.kind=="leaves" and strategy!="none":
				for obj in spell.objects:
					if obj.dead or obj.reflected or spell.age<obj.born: continue
					var relative: Vector2=lan.position+Vector2(0,-35)-obj.at
					var velocity: Vector2=obj.velocity
					var ahead: float=relative.dot(velocity)/velocity.length_squared()
					var miss: float=(relative-velocity*maxf(ahead,0)).length()
					var id: String="%d_%d"%[obj.contact.get_instance_id(),obj.bounces]
					if ahead>0 and ahead<.45 and miss<65 and not threats.has(id): threats[id]=wall
					if threats.has(id) and wall-float(threats[id])>=.15 and ahead>=-.02 and ahead<.20 and miss<65 and not sent.has(id):
						key(KEY_K,true)
						sent[id]=true
						stamp("K_leaf",{"ahead":ahead,"observed_for":wall-float(threats[id])})
			if spell.kind=="meteors" and strategy=="move":
				for obj in spell.objects:
					var local: float=spell.age-obj.born
					if local<.15 or local>1.0: continue
					if absf(lan.position.x-obj.x)<132:
						selected_side=signf(lan.position.x-obj.x)
						if is_zero_approx(selected_side): selected_side=-1
						var target_x: float=lan.position.x+selected_side*90
						if roots_at<0 and (target_x<1150 or target_x>1410): selected_side=-selected_side
						Input.action_press(&"ui_right" if selected_side>0 else &"ui_left")
						break
			if spell.kind=="meteors" and strategy=="dodge":
				for obj in spell.objects:
					var local: float=spell.age-obj.born
					var id := "meteor_dodge_%s"%obj.born
					if local>=.75 and local<.84 and absf(lan.position.x-obj.x)<100 and not sent.has(id):
						key(KEY_K,false)
						var dodge_side: float=signf(lan.position.x-obj.x)
						if roots_at<0 and absf(lan.position.x-1280)>80: dodge_side=signf(1280-lan.position.x)
						key(KEY_D,dodge_side>=0)
						key(KEY_A,dodge_side<0)
						key(KEY_L,true)
						sent[id]=true
						stamp("L_meteor",{"local":local,"meteor_x":obj.x,"ground_action":lan.ground_action_state})
			if spell.kind=="meteors" and strategy=="jump":
				if first_jump<0 and spell.age>=.4:
					key(KEY_W,true)
					first_jump=wall
					stamp("W_meteor")
				elif first_jump>=0 and wall-first_jump>=.5 and not sent.has("double_jump"):
					key(KEY_W,true)
					sent["double_jump"]=true
					stamp("W_double")
		if roots_at>=0 and input_at<0 and wall-roots_at>=delay and strategy!="none":
			# The disappearance is the visible cue, with explicit human reaction delay.
			Input.action_release(&"ui_left")
			Input.action_release(&"ui_right")
			key(KEY_K,false)
			key(KEY_D,true)
			key(KEY_U,true)
			input_at=wall
			stamp("U",{"reaction":wall-roots_at,"defense":lan.defense_state,"attack":lan.attack_state})
		if strategy=="dodge" and input_at>=0 and teleported_at<0 and lan.ground_action_state==LanPlayer.GroundActionState.NONE and lan.attack_state==LanPlayer.AttackState.NONE and not lan.hit_reaction_active and f%2==0:
			key(KEY_D,true)
			key(KEY_U,true)
		if input_at>=0 and teleported_at<0 and absf(lan.position.x-initial_x)>350:
			teleported_at=wall
			stamp("teleport",{"since_input":wall-input_at})
			await snap("escaped")
		if lan.combat_stats.health<last_hp:
			if first_damage<0: first_damage=wall
			stamp("health_loss",{"damage":last_hp-lan.combat_stats.health})
			last_hp=lan.combat_stats.health
			await snap("damage")
		if lan.combat_stats.health<=28: break
		all_casts=next==order.size()
		if action>9.0 and all_casts and deer.spells.is_empty(): break
		await physics_frame
		wall+=1.0/60.0
	release()
	var report := {"route":route_name,"legal":legal,"casts":next,"hp":lan.combat_stats.health,"roots_at":roots_at,"finished":deer.spells.is_empty(),
		"u_at":input_at,"teleport_at":teleported_at,"first_damage":first_damage,"peak_non_leaf":max_slots,"peak_live":peak_live,"events":events.duplicate(true)}
	reports.append(report)
	print("WIND_OVERLAP_RESULT "+JSON.stringify(report))
	check(legal and max_slots<=2,"Legal scheduling and two non-leaf cap: "+route_name)
	room.encounter.stop()
	await wait_frames(2)

func run() -> void:
	var save := use_memory_progress()
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	(root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested=true
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	check(not room.player.combat_stats.refill_health_on_depletion,"Production player has no lethal refill")
	if "--review" in OS.get_cmdline_user_args():
		await route([1],.15,"guard",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,4],.20,"guard",BattleAssistSettingsService.Difficulty.NIGHTMARE)
		await route([1,0,2],.15,"move",BattleAssistSettingsService.Difficulty.HARD)
	elif "--dodge-review" in OS.get_cmdline_user_args():
		await route([1,0,2],.10,"dodge",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,2],.15,"dodge",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	elif "--followup" in OS.get_cmdline_user_args():
		await route([1,0,2],.10,"dodge",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,2],.15,"dodge",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,2],.10,"jump",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,2],.15,"jump",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	else:
		for delay in [0.0,.10,.15,.20,.25]: await route([1],delay,"guard",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,4],.15,"guard",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,4],.20,"guard",BattleAssistSettingsService.Difficulty.NIGHTMARE)
		await route([1,0,2],.15,"move",BattleAssistSettingsService.Difficulty.HARD)
		await route([1,0,2],.20,"move",BattleAssistSettingsService.Difficulty.NIGHTMARE)
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("routes.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(reports,"\t"))
	room.encounter.stop()
	current_scene=null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER WIND LEGAL OVERLAP INVESTIGATION")

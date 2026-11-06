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
	if "--blast-review" in OS.get_cmdline_user_args() and not label.begins_with("settlement_"): return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
func setup_at(x:=250.0, player_x:=650.0) -> void:
	key(KEY_K,false)
	key(KEY_L,false)
	key(KEY_U,false)
	key(KEY_D,false)
	deer.restart_duel()
	deer.transform_left=0
	deer.invulnerable=false
	deer.position=Vector2(x,555)
	deer.wait_left=999
	lan.reset_after_map_fall(Vector2(player_x,555))
	lan.combat_stats.max_health=1000
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	lan.instant_dash_cooldown_remaining=0
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
	var probe_safe := true
	var held_cast := true
	var captured_blasts := {}
	var radii: Array=[]
	var aligned := true
	var captured_phases := {}
	var blast_aligned := true
	var blast_times: Array=[]
	var between_safe := true
	var previous_hp := 1000
	var previous_blasts := 0
	for f in 1100:
		key(KEY_K,false)
		key(KEY_L,false)
		deer.wait_left=999
		if not is_instance_valid(spell): break
		var index: int=spell.core_contacts
		if dodge and not sent.has("dodge") and spell.age>=spell.core_beat_time(0)-.07:
			key(KEY_L,true)
			sent["dodge"]=true
		slow_seen=slow_seen or deer.action_clock.dodge_remaining>0
		# Read the visible compression, rather than relying on the old invisible timer.
		var readable: bool=is_instance_valid(spell.core_orb) and spell.core_orb.compression>=.25
		if index<parries and not sent.has(index) and readable:
			key(KEY_K,true)
			sent[index]=true
		last_contacts=spell.core_contacts
		last_successes=spell.core_successes
		last_explosions=spell.core_explosions
		if spell.core_explosions==0: probe_safe=probe_safe and lan.combat_stats.health==1000
		if spell.age<spell.core_release_time(): held_cast=held_cast and deer.cast_index==4
		radii=spell.explosion_radii.duplicate()
		blast_times=spell.settlement_beats.duplicate(true)
		if spell.core_explosions==previous_blasts: between_safe=between_safe and lan.combat_stats.health==previous_hp
		previous_blasts=spell.core_explosions
		previous_hp=lan.combat_stats.health
		for i in spell.settlement_fx.size():
			if not is_instance_valid(spell.settlement_fx[i]): continue
			var fx: Node2D=spell.settlement_fx[i]
			blast_aligned=blast_aligned and fx.detonated==(spell.core_explosions>i)
			var blast_phase := "charge" if not fx.detonated and fx.compression>.88 else ("impact" if fx.detonated and fx.age-fx.charge<.035 else ("afterglow" if fx.detonated and fx.age-fx.charge>.10 and fx.age-fx.charge<.14 else ""))
			var shot := "settlement_%d_%d_%s"%[parries,i+1,blast_phase]
			if i in [0,2,8] and not blast_phase.is_empty() and not captured_phases.has(shot):
				captured_phases[shot]=true
				await capture(shot)
		# Capture the actual handoff, not only the settled pulse: the body must stay coherent.
		var shape_phase := ""
		if spell.age>1.40 and spell.age<1.65: shape_phase="staff"
		elif spell.age>1.88 and spell.age<1.98: shape_phase="flight"
		elif is_instance_valid(spell.core_orb) and spell.core_orb.age<.06: shape_phase="settled"
		if not shape_phase.is_empty() and not captured_phases.has(shape_phase):
			captured_phases[shape_phase]=true
			await capture("wind_body_%d_%s"%[parries,shape_phase])
		if is_instance_valid(spell.core_orb):
			aligned=aligned and spell.core_orb.released==spell.core_contacts and absf(spell.core_orb.age-(spell.age-float(spell.pulse_spec.t)))<.0001
			var phase := ""
			if index==0 and spell.core_orb.compression>.85: phase="first_compress"
			elif index in [1,6,9] and spell.core_orb.release_light>.85: phase="release_%d"%index
			elif index==1 and spell.core_orb.release_light<=0 and spell.core_orb.compression<.1: phase="reset"
			if not phase.is_empty() and not captured_phases.has(phase):
				captured_phases[phase]=true
				await capture("wind_pulse_%d_%s"%[parries,phase])
		if spell.core_explosions in [1,9] and not captured_blasts.has(spell.core_explosions):
			captured_blasts[spell.core_explosions]=true
			await capture("wind_core_%d_%sblast_%d"%[parries,"dodge_" if dodge else "",spell.core_explosions])
		if f in [60,130,215]: await capture("wind_core_%d_%d"%[parries,f])
		await physics_frame
	key(KEY_K,false)
	key(KEY_L,false)
	check(probe_safe,"All nine contact beats deal zero HP damage, including misses")
	check(aligned,"All nine visual releases and contacts share the action clock")
	check(held_cast,"The caster does not begin a followup during the nine beats or settlement")
	var growing := true
	for i in range(1,radii.size()): growing=growing and radii[i]>radii[i-1]
	check(growing,"Every settlement blast increases its actual collision radius")
	check(last_contacts==9,"Wind core resolves all nine contacts")
	var expected := 9 if difficulty==BattleAssistSettingsService.Difficulty.NORMAL and parries>0 else parries
	check(last_successes==expected,"Real K successes: expected %d, got %d"%[expected,last_successes])
	check(last_explosions==9-last_successes,"Exactly one explosion per un-parried contact")
	check(blast_aligned,"Every owed blast has a synchronized visual and damage onset")
	check(between_safe,"Every charge and afterglow is harmless between discrete blast onsets")
	var slowing := true
	for i in range(2,blast_times.size()):
		var previous_gap: float=blast_times[i-1].age-blast_times[i-2].age
		var gap: float=blast_times[i].age-blast_times[i-1].age
		slowing=slowing and gap>previous_gap+.025
	check(slowing,"Observed blast intervals progressively slow down")
	print("SETTLEMENT_ROUTE "+JSON.stringify(blast_times))
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
	if "--tornado-refill" in OS.get_cmdline_user_args():
		await tornado_refill_route()
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND PRACTICE REFILL")
		return
	if "--tornado-manual" in OS.get_cmdline_user_args():
		await tornado_manual_route()
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND MANUAL SPELL OWNERSHIP")
		return
	if "--tornado-phantom" in OS.get_cmdline_user_args():
		await tornado_phantom_route()
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND TORNADO PHANTOM")
		return
	if "--blast-review" in OS.get_cmdline_user_args():
		await core_route(0,BattleAssistSettingsService.Difficulty.HARD)
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND CORE SETTLEMENT")
		return
	if "--core-review" in OS.get_cmdline_user_args():
		await core_pause_route()
		await settlement_pause_route()
		for route in [[0,1],[1,0],[6,1],[9,1]]: await core_route(route[0],route[1])
		await core_route(0,BattleAssistSettingsService.Difficulty.HARD,true)
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND CORE RHYTHM")
		return
	if "--profile" in OS.get_cmdline_user_args():
		await render_profile()
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND RENDER PROFILE")
		return
	if "--review" in OS.get_cmdline_user_args():
		setup_at()
		deer.start_spell(2)
		while deer.spells.is_empty(): await step(1)
		var meteor: Node2D=deer.spells.back()
		while meteor.objects.is_empty() or not meteor.objects[0].landed: await step(1)
		await capture("wind_meteor_blast_start")
		await step(6)
		await capture("wind_meteor_blast_hold")
		await core_route(0,BattleAssistSettingsService.Difficulty.HARD)
		await overlap_profile()
		await ai_route()
		current_scene=null
		room.free()
		await process_frame
		expect_save_untouched()
		finish("WIND VISUAL REVIEW")
		return
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
			await step(90)
			check(spell.root_count>2,"Converging tornadoes keep growing painted roots behind them")
			check(spell.objects[2].sprite.texture.atlas.resource_path.contains("root_painted"),"Root forest uses the root phase artwork")
		if index==2:
			await step(95)
			check(spell.objects.size()==7,"All seven meteors spawn without a two-hit cap")
			check(spell.objects.all(func(o): return o.storm==null),"Meteor landings have no lingering tornado")
		if index==3:
			check(spell.objects.size()==6,"One deer phantom leaves a five-section wind path")
		await step(520)
		check(deer.spells.is_empty(),"Hazards expire naturally: %d"%index)
	await core_route(0,BattleAssistSettingsService.Difficulty.HARD)
	await core_route(1,BattleAssistSettingsService.Difficulty.NORMAL)
	await core_route(6,BattleAssistSettingsService.Difficulty.HARD)
	await core_route(9,BattleAssistSettingsService.Difficulty.HARD)
	await core_route(0,BattleAssistSettingsService.Difficulty.HARD,true)
	await core_pause_route()
	await settlement_pause_route()
	await escape_route("U")
	await escape_route("wait")
	await escape_route("walk")
	await escape_route("early_U")
	await leaf_routes()
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
	await step(90)
	var meteors: Node2D=deer.spells.back()
	deer.start_spell(0)
	await step(45)
	check(is_instance_valid(meteors) and deer.has_spell("meteors") and deer.has_spell("leaves"),"Remaining meteors finish across a leaf followup")
	await capture("wind_overlap")
	await overlap_profile()
	setup_at()
	deer.opening=0
	for i in DeerDuelBoss.COUNTER_PARRIES:
		deer.on_attack_parried(CombatAttackData.new(StringName("bead_%d" % i),deer,0,0,0,0),deer.position)
	deer.opening=.62
	check(deer.counter_ready and not deer.poise_broken,"Six successful parries offer a throw without poise stun")
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
	await spell_limit_route()
	await tornado_manual_route()
	await tornado_refill_route()
	await ai_route()
	lan.combat_stats.max_health=100
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER WIND")

func tornado_refill_route() -> void:
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	var deaths: Array=[]
	var on_death := func(): deaths.append(true)
	lan.combat_stats.health_depleted.connect(on_death)
	for followup in [0,2,3]:
		setup_at()
		lan.combat_stats.max_health=100
		lan.combat_stats.restore_health()
		deer.start_spell(1)
		await step(110)
		var tornado: Node2D=deer.spells.back()
		var before: float=tornado.age
		lan.combat_stats.health=1
		deaths.clear()
		await capture("refill_before_%d"%followup)
		deer.start_spell(followup)
		for frame in 220:
			await step(1)
			if lan.combat_stats.health>1: break
		check(lan.combat_stats.health>1 and not results.is_empty(),"Followup %d causes a real lethal hit and practice HP refill"%followup)
		check(deaths.is_empty(),"Practice refill must not broadcast defeat during followup %d"%followup)
		await step(3)
		var intact := is_instance_valid(tornado)
		if intact:
			intact=tornado.age>before and not tornado.finished and tornado.objects[0].fx.is_visible_in_tree() and tornado.objects[1].fx.is_visible_in_tree()
			intact=intact and tornado.objects.any(func(o): return o.type=="root" and o.sprite.visible)
		check(intact,"Lethal followup %d preserves advancing twin tornadoes and visible roots"%followup)
		print("REFILL_ROUTE "+JSON.stringify({"followup":followup,"hp":lan.combat_stats.health,"death_signals":deaths.size(),"tornado_alive":intact,"results":results}))
		await capture("refill_after_%d"%followup)
	lan.combat_stats.health_depleted.disconnect(on_death)
	deer.restart_duel()
	await step(2)
	check(deer.spells.is_empty(),"Explicit retry still cleans up practice spells")

func tornado_manual_route() -> void:
	room.set_combat_simulation(false)
	for followup in [0,2,3,4]:
		deer.restart_duel()
		room.play_action(1)
		await step(110)
		var tornado: Node2D=deer.spells.back()
		var before: float=tornado.age
		room.play_action(followup)
		var preserved: bool=is_instance_valid(tornado) and not tornado.finished
		await step(65)
		preserved=preserved and is_instance_valid(tornado)
		if preserved: preserved=tornado.age>before and tornado.objects[0].fx.is_visible_in_tree() and tornado.objects[1].fx.is_visible_in_tree()
		check(preserved,"Development-room action %d preserves the already-cast twin tornadoes and their clock"%followup)
		await capture("manual_tornado_followup_%d"%followup)
	deer.restart_duel()
	room.play_action(1)
	await step(110)
	var retained: Node2D=deer.spells.back()
	room.play_action(2)
	await step(110)
	var serial: int=deer.spell_serial
	room.play_action(3)
	await step(2)
	check(deer.cast_index==-1 and deer.spell_serial==serial and is_instance_valid(retained),"Manual third non-leaf request waits without evicting either existing spell")
	room.play_action(0)
	await step(40)
	check(deer.has_spell("leaves") and deer.active_spell_slots()==2 and is_instance_valid(retained),"Manual leaf request can join two existing spells without clearing them")
	await step(70)
	serial=deer.spell_serial
	room.play_action(0)
	await step(2)
	check(deer.spell_serial==serial and deer.cast_index==-1,"Manual leaf button respects the same internal cooldown")
	while is_instance_valid(retained) and not retained.roots_released: await step(1)
	check(is_instance_valid(retained) and absf(retained.release_age-6.15)<.03,"Root forest releases on its original beat after manual followups")
	while is_instance_valid(retained) and retained.age<7.34: await step(1)
	check(is_instance_valid(retained) and not retained.objects[0].fx._air.items.is_empty() and not retained.objects[1].fx._air.items.is_empty(),"Both tornadoes survive through their complete authored active phase")
	await step(90)
	check(not is_instance_valid(retained),"Twin tornadoes still retire naturally after their own ending")
	room.set_combat_simulation(true)

func tornado_phantom_route() -> void:
	for variant in [0,1]:
		setup_at()
		(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
		deer.start_spell(1)
		await step(110)
		var tornado: Node2D=deer.spells.back()
		var before: float=tornado.age
		var ids := [tornado.objects[0].fx.get_instance_id(),tornado.objects[1].fx.get_instance_id()]
		await capture("tornado_before_phantom_%d"%variant)
		deer.tail_variant=variant
		deer.start_spell(3)
		var intact := true
		var visible_roots := true
		for frame in 210:
			if not is_instance_valid(tornado):
				intact=false
				break
			for i in 2:
				var fx: Node2D=tornado.objects[i].fx
				intact=intact and is_instance_valid(fx) and fx.get_instance_id()==ids[i] and fx.visible and not fx._air.items.is_empty()
			visible_roots=visible_roots and tornado.objects.filter(func(o): return o.type=="root").any(func(o): return o.sprite.visible)
			if frame in [45,85,145]: await capture("tornado_during_phantom_%d_%d"%[variant,frame])
			await step(1)
		check(intact and tornado.age>before+3,"AI-body followup preserves both tornado renderers through phantom variant %d"%variant)
		check(visible_roots,"Phantom variant %d leaves the root forest visible before its release beat"%variant)
		print("TORNADO_PHANTOM "+JSON.stringify({"variant":variant,"before":before,"after":tornado.age,"roots":tornado.root_count,"released":tornado.roots_released}))
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)

func spell_limit_route() -> void:
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	deer.start_spell(1)
	check(deer.active_spell_slots()==1,"An unreleased non-leaf cast reserves its performance slot")
	await step(45)
	var tornado: Node2D=deer.spells.back()
	deer.start_spell(2)
	check(deer.active_spell_slots()==2,"A second cast's tell cannot leave an uncounted third slot")
	await step(45)
	deer.cooldowns=[0.0,0.0,0.0,0.0,0.0]
	check(deer.active_spell_slots()==2,"The two tornado bodies count as one skill alongside the meteor volley")
	var leaf_only := true
	for i in 40: leaf_only=leaf_only and deer.choose_spell(350)==0
	check(leaf_only,"At two active non-leaf skills the AI may still choose the independent leaf volley")
	deer.cooldowns[0]=1.0
	check(deer.choose_spell(350)==-1,"Full slots and a cooling leaf volley wait instead of forcing a fallback spell")
	tornado.retire()
	check(deer.can_schedule_spell(3),"A completed skill releases its slot for the next ordinary spell")
	deer.start_spell(0)
	await step(40)
	check(deer.active_spell_slots()==1,"A released leaf volley never consumes a non-leaf slot")
	check(deer.cooldowns[0]>5.8 and not deer.can_schedule_spell(0),"Leaf release starts its independent six-action-second cooldown")
	var cooldown: float=deer.cooldowns[0]
	deer.action_clock.pause(.30)
	await step(9)
	check(is_equal_approx(cooldown,deer.cooldowns[0]),"Leaf internal cooldown follows the shared paused action clock")
	deer.restart_duel()
	check(deer.active_spell_slots()==0 and deer.cooldowns[0]==0,"Retry clears reservations and leaf internal cooldown")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)

func ai_route() -> void:
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	lan.combat_stats.max_health=100
	lan.combat_stats.restore_health()
	# Reproducible weighted AI coverage; a random 55s window can legitimately omit a spell.
	deer._rng.seed=20261106
	deer.wait_left=0
	var max_slots := 0
	var leaf_times: Array[float]=[]
	var seen := {}
	var tornado_lifetimes := {}
	var previous_hp := 100
	var refills := 0
	var roots_intact := true
	for f in 3300:
		if lan.combat_stats.health>previous_hp: refills+=1
		previous_hp=lan.combat_stats.health
		max_slots=maxi(max_slots,deer.active_spell_slots())
		for spell in deer.spells:
			if is_instance_valid(spell) and spell.kind=="tornado":
				tornado_lifetimes[spell.serial]={"node":spell,"age":spell.age}
				if spell.age>2 and spell.age<6.12:
					roots_intact=roots_intact and spell.objects.any(func(o): return o.type=="root" and o.sprite.visible)
			if not is_instance_valid(spell) or spell.kind!="leaves" or seen.has(spell.serial): continue
			seen[spell.serial]=true
			leaf_times.append(deer._time-spell.age)
		await physics_frame
	var used := {}
	for move in deer.move_history: used[move]=true
	print("WIND_AI_ROUTE "+JSON.stringify(deer.move_history))
	var spaced := true
	for i in range(1,leaf_times.size()): spaced=spaced and leaf_times[i]-leaf_times[i-1]>=5.999
	check(max_slots<=2,"Full AI never overlaps more than two non-leaf skills, including cast tells")
	check(leaf_times.size()>=2 and spaced,"Full AI respects the independent leaf cooldown across repeated volleys")
	print("WIND_AI_LIMITS "+JSON.stringify({"peak_non_leaf":max_slots,"leaf_release_times":leaf_times}))
	check(used.size()==5,"Adaptive full-health combat selects all five ordinary spells")
	check(deer.move_history.count(&"core")>=2,"Wind core recurs as an ordinary spell, without ultimate health gate")
	check(deer.position.x>deer.world_min_x and deer.position.x<deer.world_max_x,"Active positioning remains in arena")
	var complete_lifetimes := true
	for lifetime in tornado_lifetimes.values():
		if not is_instance_valid(lifetime.node): complete_lifetimes=complete_lifetimes and lifetime.age>=8.31
	check(refills>0,"Full AI exercises ordinary 100 HP depletion and automatic refill")
	check(not tornado_lifetimes.is_empty() and complete_lifetimes and roots_intact,"Full AI retains every tornado until natural retirement and roots until their release beat")
	print("WIND_AI_REFILL "+JSON.stringify({"refills":refills,"tornadoes":tornado_lifetimes.size(),"complete_lifetimes":complete_lifetimes,"roots_intact":roots_intact}))
	deer.restart_duel()
	check(deer.spells.is_empty() and not deer.counter_ready,"Retry clears all spell contacts and rewards")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)

func core_pause_route() -> void:
	setup_at()
	deer.start_spell(4)
	var spell: Node2D=deer.spells.back()
	while spell.age<2.15: await step(1)
	var before: float=spell.age
	var visual: float=spell.core_orb.age
	deer.action_clock.pause(.30)
	await step(9)
	check(is_equal_approx(before,spell.age) and is_equal_approx(visual,spell.core_orb.age),"Hit-stop freezes the same preparation phase and contact clock")
	while spell.core_contacts==0: await step(1)
	check(spell.core_contacts==1 and spell.core_orb.released==1,"Resuming hit-stop releases exactly one visual and contact")
	await step(2)
	before=spell.age
	deer.action_clock.start_dodge_slow(.6)
	await step(12)
	check(spell.age-before<.08 and is_equal_approx(spell.core_orb.age,spell.age-float(spell.pulse_spec.t)),"Perfect-dodge slow motion also preserves visual/contact phase")

func settlement_pause_route() -> void:
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.start_spell(4)
	var spell: Node2D=deer.spells.back()
	while spell.age<4.91: await step(1)
	var before: float=spell.age
	var visual: float=spell.settlement_fx[0].age
	deer.action_clock.pause(.30)
	await step(9)
	check(is_equal_approx(spell.age,before) and is_equal_approx(spell.settlement_fx[0].age,visual),"Settlement charge visual freezes with the same action clock")
	while spell.core_explosions==0: await step(1)
	check(spell.core_explosions==1 and spell.settlement_fx[0].detonated,"Settlement resumes into exactly one synchronized blast")
	deer.restart_duel()
	await step(2)
	check(not is_instance_valid(spell),"Retry frees settlement effects and contacts together")

func escape_route(route: String) -> void:
	setup_at(250,640)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.start_spell(1)
	while deer.spells.is_empty(): await step(1)
	var spell: Node2D=deer.spells.back()
	var hp: int=lan.combat_stats.health
	var x: float=lan.position.x
	if route=="early_U":
		while spell.age<float(spell.config.release_at)-.65: await step(1)
		lan.facing_direction=1
		key(KEY_U,true)
		await step(1)
		key(KEY_U,false)
	while not spell.roots_released: await step(1)
	check(spell.root_count>12,"Roots fill the area behind both moving tornadoes")
	check(spell.objects.filter(func(o): return o.type=="root").all(func(o): return not o.sprite.visible and (not is_instance_valid(o.contact) or o.contact.hitbox.attack==null)),"All original and newly grown roots disappear and disarm on the escape beat")
	await capture("wind_escape_open")
	if route=="U":
		lan.facing_direction=1
		key(KEY_U,true)
		await step(1)
		key(KEY_U,false)
	elif route=="walk": key(KEY_D,true)
	await step(70)
	key(KEY_D,false)
	check(lan.combat_stats.health==hp if route=="U" else lan.combat_stats.health<hp,"Real U escapes; waiting, walking or teleporting early take damage: %s"%route)
	if route=="U": check(lan.position.x-x>400,"Escape uses the real 480-pixel U teleport")

func leaf_routes() -> void:
	setup_at()
	deer.start_spell(0)
	while deer.spells.is_empty(): await step(1)
	var spell: Node2D=deer.spells.back()
	await step(135)
	check(spell.objects.all(func(o): return o.bounces>0),"All three blades bounce off screen edges")
	check(spell.objects[0].born<spell.objects[1].born and spell.objects[1].born<spell.objects[2].born,"Three blade releases stay staggered")
	check(spell.objects.all(func(o): return spell.leaf_bounds.grow(.1).has_point(o.at)),"Bouncing blades stay inside the combat viewport")
	var obj: Dictionary=spell.objects[0]
	obj.at=spell.leaf_bounds.end-Vector2(1,1)
	obj.velocity=Vector2(200,200)
	spell._move_leaf(obj,0,.02)
	check(obj.velocity.x<0 and obj.velocity.y<0,"A corner hit reflects both axes without a diagonal shortcut")
	await capture("wind_leaf_bounce")
	for red in [false,true]:
		setup_at()
		deer.start_spell(0)
		while deer.spells.is_empty(): await step(1)
		spell=deer.spells.back()
		await step(60)
		var index := 2 if red else 0
		obj=spell.objects[index]
		for i in 3:
			if i!=index: spell._end_leaf(spell.objects[i])
		obj.at=lan.position+Vector2(45,-40)
		obj.velocity=Vector2(-300,0)
		var hp: int=deer.combat_stats.health
		key(KEY_K,true)
		await step(1)
		key(KEY_K,false)
		await step(20)
		check(obj.reflected if red else obj.dead,"Real K reflects red / clears green blade: red=%s"%red)
		await step(70)
		if red: check(deer.combat_stats.health==hp-24,"Reflected blade reaches the caster for the existing 24 damage")

func overlap_profile() -> void:
	setup_at()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	deer.start_spell(1)
	await step(60)
	deer.start_spell(2)
	await step(60)
	deer.start_spell(0)
	await step(40)
	deer.start_spell(4)
	var max_nodes := 0
	var max_contacts := 0
	var max_pieces := 0
	var max_draws := 0
	for f in 450:
		deer.wait_left=999
		var contacts := 0
		var pieces := 0
		for spell in deer.spells:
			if not is_instance_valid(spell): continue
			contacts+=spell.contacts.size()
			for fx in spell.visuals.running:
				if is_instance_valid(fx) and "capacity" in fx: pieces+=fx.capacity
		max_contacts=maxi(max_contacts,contacts)
		max_pieces=maxi(max_pieces,pieces)
		max_nodes=maxi(max_nodes,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		max_draws=maxi(max_draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if f in [40,110,200]: await capture("wind_stack_%d"%f)
		await physics_frame
	# Capture PNGs stall this route; measure frame times separately with --profile.
	print("WIND_OVERLAP_PROFILE "+JSON.stringify({"nodes":max_nodes,"contacts":max_contacts,"pieces":max_pieces,"draw_calls":max_draws,"renderer":DisplayServer.get_name()}))
	check(max_contacts<60,"Finished pulse contacts are reclaimed during overlapping spells")
	check(max_pieces<2200,"GPU swarms remain bounded during four-spell overlap")
	# Allow the new progressive settlement and its existing hit-stop, with a bounded timeout.
	for f in 600:
		if deer.spells.is_empty(): break
		await step(1)
	if not deer.spells.is_empty():
		print("WIND_CLEANUP_REMAINING "+JSON.stringify(deer.spells.map(func(s): return {"kind":s.kind,"age":s.age,"settlement_end":s.core_release_time() if s.kind=="core" else 0})))
	check(deer.spells.is_empty(),"Overlapping spells reclaim all effects and collision sources")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)

func render_profile() -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	for label in ["baseline","leaves","tornado","meteors","core","stack","stack_no_swarm","stack_no_wind"]:
		setup_at()
		var indices: Array = []
		match label:
			"leaves": indices=[0]
			"tornado": indices=[1]
			"meteors": indices=[2]
			"core": indices=[4]
			"stack", "stack_no_swarm", "stack_no_wind": indices=[1,2,0,4]
		for index in indices:
			deer.start_spell(index)
			await step(45)
		var samples: Array[float]=[]
		var cpu: Array[float]=[]
		var gpu: Array[float]=[]
		var draw_calls := 0
		for f in 150:
			for spell in deer.spells:
				if label=="stack_no_swarm":
					for fx in spell.visuals.running:
						if "capacity" in fx: fx.hide()
				if label=="stack_no_wind": spell.visuals.hide()
			var before := Time.get_ticks_usec()
			await step(1)
			if f<30: continue
			samples.append((Time.get_ticks_usec()-before)/1000.0)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			draw_calls=maxi(draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		for sample in [samples,cpu,gpu]: sample.sort()
		print("WIND_RENDER_PROFILE "+JSON.stringify({"case":label,"wall_ms_median":samples[60],"wall_ms_p95":samples[114],"render_cpu_ms_p95":cpu[114],"render_gpu_ms_p95":gpu[114],"draw_calls":draw_calls}))
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)

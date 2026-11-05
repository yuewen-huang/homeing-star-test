extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: Node2D
var lan: LanPlayer
var contacts: Array = []

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)

func release() -> void:
	for code in [KEY_K,KEY_J,KEY_W,KEY_L]: key(code,false)
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")

func walk_to(x: float) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	if absf(x-lan.position.x)>5: Input.action_press(&"ui_right" if x>lan.position.x else &"ui_left")

func gap_near(x: float) -> float:
	var best := x
	var distance := INF
	for candidate in range(55,1225,8):
		var safe := true
		for h in deer.arena.hazards:
			if absf(candidate-h.x)<55: safe=false
		if safe and absf(candidate-x)<distance:
			best=candidate
			distance=absf(candidate-x)
	return best

func reset_pair(x: float) -> void:
	release()
	room._combat_result=""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.wait_left=999
	deer.pressure.selected=2
	deer.position=Vector2(820 if x<640 else 360,555)
	lan.reset_after_map_fall(Vector2(x,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.parry_chain.cancel()
	contacts.clear()

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func sky_route(x: float) -> void:
	reset_pair(x)
	for f in 4: await physics_frame
	deer.start_phrase(2)
	var wave := 0
	var goal := x
	var locked: Array = []
	var stable := true
	var opening_seen := false
	var old_hp: int = deer.combat_stats.health
	var captures := {}
	for f in 440:
		key(KEY_J,false)
		if deer.arena.wave_count!=wave:
			wave=deer.arena.wave_count
			goal=gap_near(lan.position.x)
			locked=deer.arena.hazards.map(func(h): return h.x)
		if not deer.arena.hazards.is_empty():
			stable=stable and deer.arena.hazards.all(func(h): return locked.has(h.x))
		if deer.age>=deer.SKY_RETURN or deer.opening>0:
			goal=deer._sky_return_x+(90 if lan.position.x>deer._sky_return_x else -90)
		walk_to(goal)
		if deer.opening>0:
			if not opening_seen: check(deer.opening>1.70,"Sky return grants the promised 1.8-second punish")
			opening_seen=true
			if absf(lan.position.x-deer.position.x)<135: key(KEY_J,true)
		if x==380 and deer.move==&"sky_cast":
			for item in [["sky_warning",1.05],["sky_active",1.47],["sky_second",2.15],["sky_return",2.65]]:
				if deer.age>=item[1] and not captures.has(item[0]):
					captures[item[0]]=true
					await capture(item[0])
		if opening_seen and deer.opening<=0: break
		await physics_frame
	release()
	check(wave==2,"Two readable rain waves, x=%d" % x)
	check(stable,"Warned columns never chase the moving player")
	check(lan.combat_stats.health==100,"Ordinary walking escapes rain without damage, x=%d" % x)
	check(deer.combat_stats.health<old_hp,"Real J reaches the returned deer, x=%d" % x)
	check(not deer.invulnerable and deer.animated_sprite.visible,"Return restores foreground vulnerability")
	check(deer.arena.probes().is_empty() and deer.arena.cast_alpha==0,"Recovery contains no hidden rain or lingering caster")
	deer.cancel_duel()

func ground_route(x: float) -> void:
	reset_pair(x)
	deer.pressure.selected=1
	for f in 4: await physics_frame
	deer.start_phrase(1)
	var goal := x
	var drop_goal := NAN
	var bursts := 0
	var opening_seen := false
	var old_hp: int = deer.combat_stats.health
	for f in 420:
		key(KEY_J,false)
		if deer.arena.burst_count>bursts:
			bursts=deer.arena.burst_count
			goal=gap_near(lan.position.x)
		if deer.move==&"drop":
			if is_nan(drop_goal): drop_goal=deer._aim+(180 if deer._aim<640 else -180)
			goal=drop_goal
		if deer.opening>0:
			opening_seen=true
			goal=deer.position.x+(90 if lan.position.x>deer.position.x else -90)
			if absf(lan.position.x-deer.position.x)<135:
				lan.facing_direction=signf(deer.position.x-lan.position.x)
				key(KEY_J,true)
		walk_to(goal)
		key(KEY_W,deer.opening<=0 and deer.move==&"rush" and deer.age>=.45 and deer.age<.65)
		if opening_seen and deer.opening<=0: break
		await physics_frame
	release()
	check(bursts==2,"Both heavy stomp and jump landing erupt, x=%d" % x)
	check(lan.combat_stats.health==100,"Ground gaps, drop avoidance and jumping rush remain reachable, x=%d" % x)
	check(opening_seen,"Ground phrase returns to an attack window")
	check(deer.combat_stats.health<old_hp,"Real J punishes the ground phrase after evading, x=%d" % x)
	deer.cancel_duel()

func ground_beat_contract() -> void:
	# Reference contract: the slam, harmless travelling light, sudden pillars,
	# and held threat are distinct observable stages, on the production clock.
	var feedback := root.get_node("CombatFeedback")
	feedback.set_process(false)
	for jumping in [false,true]:
		reset_pair(380)
		deer.set_physics_process(false)
		lan.set_physics_process(false)
		deer.manual_control=true
		if jumping: deer.start_move(1,640)
		else: deer.start_phrase(1)
		var impact_at := -1.0
		var release_at := -1.0
		var clock := 0.0
		var warned := false
		var harmless := true
		var stable := true
		var full_height := false
		var held := false
		var retired := false
		var shaken := false
		var settled := false
		var locked: Array = []
		var attack_key := &""
		var body_key := &""
		for f in 210:
			deer._physics_process(1.0/60)
			feedback._process(1.0/60)
			clock+=1.0/60
			var active: bool = not deer.arena.probes().is_empty()
			if not deer.arena.hazards.is_empty() and impact_at<0:
				impact_at=clock
				locked=deer.arena.hazards.map(func(h): return h.x)
				if jumping and deer.attack_hitbox.attack!=null: body_key=deer.attack_hitbox.attack.evasion_key
			if impact_at>=0:
				shaken=shaken or root.get_camera_2d().offset.length()>1
				stable=stable and deer.arena.hazards.all(func(h): return locked.has(h.x))
				if clock-impact_at<.45: harmless=harmless and not active
				warned=warned or (not active and deer.arena.warning._marks.any(func(mark): return mark.visible))
				if clock-impact_at>.26 and clock-impact_at<.43:
					settled=settled or root.get_camera_2d().offset.length()<.01
			if active and release_at<0:
				release_at=clock
				full_height=deer.arena.hazards.all(func(h): return is_equal_approx(h.base.distance_to(h.tip),h.height))
				attack_key=deer.arena.probes()[0].attack.evasion_key
			if release_at>=0:
				if clock-release_at>=.40 and clock-release_at<.46: held=held or active
				if clock-release_at>.63:
					retired=not active
					break
		check(impact_at>=0 and warned and harmless,"Landing begins a visible, harmless light-warning interval: jump=%s" % jumping)
		check(release_at-impact_at>=.48 and release_at-impact_at<=.54,"Pillars explode about half a second AFTER landing: jump=%s" % jumping)
		check(shaken and settled,"Environmental landing shake works without hitting Lan and settles before eruption")
		check(full_height,"Thin warning becomes full-height solid pillars on one frame")
		check(held and retired,"Pillars hold long enough to read, then retire their contacts")
		check(stable,"Warning positions remain locked until the pillars retire")
		if jumping: check(body_key!=&"" and body_key!=attack_key,"Delayed pillars are a separate attack from the earlier body slam")
		deer.cancel_duel()
	feedback.set_process(true)
	deer.manual_control=false

func punish_between_pillars() -> void:
	reset_pair(780)
	deer.position=Vector2(360,555)
	for f in 4: await physics_frame
	var hp: int = deer.combat_stats.health
	var previous_hp: int = hp
	var previous_lan_hp: int = lan.combat_stats.health
	deer.start_move(1,640)
	var hit_while_live := false
	for f in 180:
		key(KEY_J,false)
		if deer.age>1.20 and deer.opening<=0:
			# Lan recoils up to 28 px on a normal hit. Enter the inner half of
			# the central gap before swinging, instead of recoiling into a pillar.
			walk_to(680)
			if absf(lan.position.x-680)<10:
				lan.facing_direction=-1
				key(KEY_J,true)
		if not deer.arena.probes().is_empty() and deer.combat_stats.health<previous_hp: hit_while_live=true
		previous_hp=deer.combat_stats.health
		if lan.combat_stats.health<previous_lan_hp:
			print("GAP CONTACT age=%.3f x=%.1f boss_x=%.1f" % [deer.age,lan.position.x,deer.position.x])
		previous_lan_hp=lan.combat_stats.health
		if deer.opening>0: break
		await physics_frame
	release()
	check(hit_while_live,"Real J can punish the grounded deer from a gap while pillars still stand")
	check(lan.combat_stats.health==100,"Reading the landing then entering a pillar gap is safe")
	deer.cancel_duel()

func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): room.select_boss(i)
	check(room.adapter.boss.manual_control,"New phases default to safe manual preview")
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	deer=room.adapter.boss
	lan=room.player
	var assist:=root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	if OS.get_cmdline_user_args().has("--sample"):
		await sky_route(380)
		await ground_route(380)
	else:
		for x in [80.0,380.0,800.0,1200.0]:
			await sky_route(x)
			await ground_route(x)
		for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL,BattleAssistSettingsService.Difficulty.NIGHTMARE]:
			assist.set_difficulty(difficulty)
			await sky_route(380)
			await ground_route(380)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	await punish_between_pillars()
	ground_beat_contract()
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	# Stationary player is genuinely hit; a root warning itself is harmless.
	reset_pair(640)
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	deer.arena.begin(2)
	deer.arena.rain(640)
	for f in 33: deer.arena.advance(1.0/60)
	check(lan.combat_stats.health==100 and deer.arena.probes().is_empty(),"Rain telegraph cannot hurt")
	check(deer.arena.warning._marks.all(func(mark): return not mark.visible) if assist.difficulty==BattleAssistSettingsService.Difficulty.NIGHTMARE else true,"Nightmare suppresses range bands")
	for f in 18: deer.arena.advance(1.0/60)
	check(lan.combat_stats.health<100 and contacts.size()==1,"One falling thorn hits once, through real combat settlement")
	deer.cancel_duel()
	check(deer.arena.hazards.is_empty(),"Cancel removes every foreground contact")
	reset_pair(760)
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	deer.arena.begin(1)
	deer.arena.burst(640,true)
	for f in 28: deer.arena.advance(1.0/60)
	check(lan.combat_stats.health==100 and deer.arena.probes().is_empty(),"Standing in ground warning light is harmless before the explosion")
	for f in 8: deer.arena.advance(1.0/60)
	check(lan.combat_stats.health<100 and contacts.size()==1,"The solid ground pillar deals one real hit after the warning")
	deer.cancel_duel()
	# Interruption in the initial roar remains possible; once out of the combat
	# plane the old hurtbox cannot award free damage. Retry restores everything.
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.start_phrase(2)
	for f in 100: deer._physics_process(1.0/60)
	var paused_age: float = deer.age
	var paused_scene: float = deer.arena.clock
	deer.action_clock.pause(.2)
	for f in 5: deer._physics_process(1.0/60)
	check(is_equal_approx(deer.age,paused_age) and is_equal_approx(deer.arena.clock,paused_scene),"Action pause freezes caster and every foreground thorn together")
	var hp: int=deer.combat_stats.health
	deer.receive_hit(100,lan.position)
	check(deer.invulnerable and deer.combat_stats.health==hp,"Distant caster has no hittable foreground body")
	deer.cancel_duel()
	check(not deer.invulnerable and deer.animated_sprite.visible and deer.effects.visible and deer.arena.cast_alpha==0,"Cancel restores body, VFX, vulnerability and background")
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.start_phrase(2)
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise)
	check(deer.poise_broken and not deer.pressure.active,"Real poise break interrupts the initial roar")
	check(deer.stagger_remaining>=4.9,"Shared five-second poise release remains intact")
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.manual_control=true
	deer.start_move(1,640)
	var single_drop_live := false
	var single_drop_open := false
	for f in 160:
		deer._physics_process(1.0/60)
		single_drop_live = single_drop_live or not deer.arena.probes().is_empty()
		single_drop_open = single_drop_open or (deer.opening>0 and deer.arena.probes().is_empty())
	check(single_drop_live and single_drop_open,"Standalone jump also finishes its explosion before recovery")
	var old: WeakRef = weakref(deer.arena)
	room.select_boss(0)
	await process_frame
	check(old.get_ref()==null,"Boss switch frees caster and thorn subtree")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER VINE STORM")

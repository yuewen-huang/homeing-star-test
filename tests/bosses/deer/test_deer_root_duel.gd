extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
var lan: LanPlayer
var contacts: Array[int] = []

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	deer = room.adapter.boss
	lan = room.player
	room.set_physics_process(false)
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	check(deer.manual_control and not room.combat_simulation,"Phase two defaults to protected preview")
	check(deer.phase == 2 and not deer.auto_advance_phases,"Root repertoire is its own real second-phase specimen")
	var surfaces_before := lan.sloped_ground_surfaces.size()
	for layout in 2:
		room.adapter.select_combo(6+layout)
		room.adapter.play_action(4)
		deer.set_physics_process(false)
		check(deer.terrain.layout == layout and deer.terrain.roots.size()==layout+1,"Manual root button respects the selected single/double layout")
	room.adapter.select_combo(0)
	for layout in 2:
		reset_pair()
		deer.manual_control = true
		deer.start_root_rise(layout)
		check(deer.terrain.roots.size() == layout+1,"One selected layout is created")
		for f in ceili((DeerRootDuelBoss.ROOT_PREP-.05)*60): tick()
		check(is_equal_approx(deer.terrain.roots[0].progress,0) and deer.attack_probes().is_empty(),"Roots stay harmless and underground throughout warning")
		await capture("roots_%d_warning" % layout)
		for f in 6: tick()
		check(deer.attack_probes().size()==1 and deer.attack_hitbox.attack.danger_type == 2,"Root emergence exposes the real gold contact")
		await capture("roots_%d_emerge" % layout)
		var before := deer.terrain.age
		var height := deer.terrain.ground_y_at(deer.terrain.roots[0].x)
		deer.red_parry_hold = true
		for f in 20: tick()
		check(deer.terrain.age == before and deer.terrain.ground_y_at(deer.terrain.roots[0].x)==height,"Terrain and collision freeze on the shared action hold")
		deer.red_parry_hold = false
		for f in 55: tick()
		check(deer.opening > 0 and deer.attack_probes().is_empty(),"Root attack ends in a damage-free punish window")
		for root in deer.terrain.roots:
			check(is_equal_approx(root.progress,1),"Every root is fully settled before punish")
			check(root.body is StaticBody2D and root.collision.polygon.size()==6,"Root owns a real solid collision polygon")
			check(is_equal_approx(deer.ground_y_at(root.x),555-root.height),"Boss support follows the same root top")
			lan.position = Vector2(root.x,555-root.height)
			check(is_equal_approx(lan.resolve_ground_snap_y(),deer.ground_y_at(root.x)),"Lan support matches boss and root geometry")
		check(lan.sloped_ground_surfaces.size()==surfaces_before+3*(layout+1),"Only this layout's support surfaces are registered")
		await capture("roots_%d_settled" % layout)
		deer.terrain.retire()
		var top: float = deer.terrain.roots[0].progress
		for f in 12: tick()
		check(is_equal_approx(deer.terrain.roots[0].progress,top),"Retirement first holds a readable warning")
		for f in 50: tick()
		check(deer.terrain.roots.is_empty() and lan.sloped_ground_surfaces.size()==surfaces_before,"Retired terrain unregisters every surface")
	# Full combo: earned middle opening cannot be canceled into a hidden rush.
	for facing in [-1,1]:
		reset_pair(facing)
		deer.manual_control = true
		deer.start_drop_rush(lan.position.x)
		for f in 78:
			if f == 30: lan.position.x += facing*115
			tick()
		check(deer.opening >= 1.1 and deer._chain_pending,"Drop gives the complete middle opening before combo continuation")
		check(deer.terrain.roots.size()==1 and is_equal_approx(deer.terrain.roots[0].progress,1),"Drop plants one settled root before opening")
		var seen: Array[StringName] = []
		var listener := func(id: StringName): seen.append(id)
		deer.move_started.connect(listener)
		for f in 50: tick()
		check(seen.is_empty() and deer.opening>0,"No early rush during the guaranteed punish")
		for f in 110: tick()
		check(seen.count(&"rush")==1,"Drop combo makes one bounded retreat then one announced rush")
		check(not deer._chain_pending,"Combo continuation is consumed once")
		deer.move_started.disconnect(listener)
	# A player who chases the fixed retreat endpoint can deny an unreadable rush.
	reset_pair()
	deer.manual_control = true
	deer.start_drop_rush(lan.position.x)
	for f in 240:
		if deer.move == &"": lan.position.x = deer.position.x+40
		tick()
	check(not deer._chain_pending and deer.move == &"","No space cancels continuation instead of tracking or teleporting")
	# Interrupting the opening removes the queued continuation and future root pulses.
	reset_pair()
	deer.manual_control = true
	deer.start_drop_rush(lan.position.x)
	for f in 80: tick()
	deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
	check(not deer._chain_pending and deer.attack_probes().is_empty(),"Poise break cancels queued rush")
	for f in 200: tick()
	check(deer.move == &"","Canceled combo never resumes late")
	reset_pair()
	deer.manual_control = true
	deer.start_root_rise(1)
	for f in ceili(DeerRootDuelBoss.ROOT_PREP*60)+7: tick()
	deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
	var progress: float = deer.terrain.roots[1].progress
	for f in 100: tick()
	check(deer.terrain.roots[1].progress==progress and deer.attack_probes().is_empty(),"Breaking root cast cancels its delayed second eruption")
	# Full AI skips a planted drop when the locked target would not leave wall room.
	for edge in [-1,1]:
		var safe := true
		for attempt in 20:
			reset_pair()
			deer.manual_control = false
			lan.position.x = deer.world_min_x+50 if edge<0 else deer.world_max_x-50
			deer.wait_left = 0
			deer._decision_age = .65
			deer._update_selection(1.0/60)
			safe = safe and deer.move != &"drop"
		check(safe,"Near-wall AI chooses another move instead of shifting the drop lock")
	# Real contact, no damage from merely standing on the completed shape.
	room.set_combat_simulation(true)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	for layout in 2:
		reset_pair()
		deer.manual_control = false
		deer.start_root_rise(layout)
		lan.position.x = deer.terrain.roots[0].x
		var hp := lan.combat_stats.health
		for f in 180: tick()
		check(contacts.size()==1 and contacts[0]==CombatHitResult.Type.NORMAL_HIT and lan.combat_stats.health<hp,"Undefended emergence hits once, settled roots have no contact damage")
	reset_pair()
	deer.start_root_rise(1)
	for f in 100: tick()
	deer.combat_stats.apply_health_damage(deer.combat_stats.health)
	check(deer.terrain.roots.is_empty() and lan.sloped_ground_surfaces.size()==surfaces_before,"Death clears geometry and support registration")
	deer.restart_duel()
	deer.start_root_rise(1)
	for f in 100: tick()
	var old := deer
	room.reset_room()
	await process_frame
	check(not is_instance_valid(old) and lan.sloped_ground_surfaces.size()==surfaces_before,"Room reset frees the old terrain subtree")
	room.select_boss(0)
	await process_frame
	check(lan.sloped_ground_surfaces.size()==surfaces_before,"Switching to the formal boss leaves no root floor behind")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER ROOT DUEL CONTRACTS")

func reset_pair(side := -1) -> void:
	room._combat_result = ""
	lan.set_input_frozen(false)
	deer.restart_duel()
	deer.set_physics_process(false)
	deer.wait_left = 999
	deer.position.x = 820 if side<0 else 360
	lan.reset_after_map_fall(Vector2(380 if side<0 else 800,555))
	lan.combat_stats.restore_health()
	lan.set_physics_process(false)
	lan.facing_direction = -side
	contacts.clear()

func tick() -> void:
	deer._physics_process(1.0/60)
	if deer.move == &"" and not deer._chain_pending: deer.wait_left = 999
	deer.vfx._process(1.0/60)

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

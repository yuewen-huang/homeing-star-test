extends "../support/harness.gd"
var lan: LanPlayer
var boss: MasterBoss
var box: CombatHitbox2D
var collision: CollisionShape2D
var serial := 0
var results: Array[int] = []

func fresh() -> void:
	lan.reset_after_map_fall(Vector2(0,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	boss.combat_stats.restore_poise()
	boss.poise_broken = false
	boss.red_parry_hold = false
	boss.parry_pause_remaining = 0
	boss.action_clock.clear()
	Engine.time_scale=1
	results.clear()

func activate(danger: int, offset: Vector2) -> void:
	serial += 1
	box.activate(CombatAttackData.new(StringName("catch_%d" % serial),boss,10,12,0,0,danger as CombatAttackData.DangerType))
	collision.disabled=false
	collision.global_position=lan.global_position+offset

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	lan=room.get_node("Lan")
	boss=room.get_node("MasterBoss")
	lan.set_physics_process(false)
	boss.set_process(false)
	boss.manual_control=true
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	await process_frame
	box=CombatHitbox2D.new()
	box.collision_layer=0
	box.collision_mask=4
	box.monitorable=false
	boss.add_child(box)
	box.set_physics_process(false)
	collision=CollisionShape2D.new()
	collision.shape=RectangleShape2D.new()
	(collision.shape as RectangleShape2D).size=Vector2(10,10)
	box.add_child(collision)
	box.hit_resolved.connect(func(_target: Node,result: CombatHitResult.Type) -> void: results.append(int(result)))
	var body := lan.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var original := body.shape.get_rect()
	for facing in [-1.0,1.0]:
		for danger in [0,1,2]:
			for state in [LanPlayer.DefenseState.NONE,LanPlayer.DefenseState.PARRY_STARTUP,LanPlayer.DefenseState.PARRY_ACTIVE,LanPlayer.DefenseState.PARRY_NOTHING_EARLY]:
				fresh()
				lan.defense_state=state
				activate(danger,Vector2(47*facing,-29))
				check(not collision.shape.collide(collision.global_transform,body.shape,body.global_transform),"Near blade genuinely misses the original hurtbox")
				var expected: bool = state==LanPlayer.DefenseState.PARRY_ACTIVE and danger!=2
				check(box.resolve_nearby_parries()==expected,"Extra reach only catches active manual normal/red parries")
				check(lan.combat_stats.health==100,"Parry reach never turns a missed attack into damage")
				if expected:
					var poise := boss.combat_stats.poise
					lan.defense_state=LanPlayer.DefenseState.PARRY_ACTIVE
					check(not box.resolve_nearby_parries() and boss.combat_stats.poise==poise and results.size()==1,"One attack settles once despite extended reach")
				else:
					check(box.hit_targets.is_empty(),"Rejected near contact does not consume its attack ledger")
	for offset in [Vector2(0,-75),Vector2(0,575-555)]:
		fresh()
		lan.start_parry(true)
		activate(0,offset)
		check(box.resolve_nearby_parries(),"Vertical grazing attacks can meet the guard")
	fresh()
	lan.start_parry(true)
	activate(0,Vector2(80,-29))
	check(not box.resolve_nearby_parries(),"Distant attack cannot be magnetically pulled into a parry")
	activate(0,Vector2(47,-29))
	box.collision_mask=0
	check(not box.resolve_nearby_parries(),"Guard catch respects the attack's target collision mask")
	box.collision_mask=4
	collision.disabled=true
	check(not box.resolve_nearby_parries(),"Disabled attack shape cannot use guard reach")
	collision.disabled=false
	box.deactivate()
	check(not box.resolve_nearby_parries(),"Recovery and old trails cannot settle contacts")
	check(body.shape.get_rect()==original and original.size==Vector2(28,58),"Player damage hurtbox remains exactly 28 by 58")
	# A near-missed gold attack remains live and damages only after real body overlap.
	fresh()
	lan.start_parry(true)
	activate(2,Vector2(47,-29))
	check(not box.resolve_nearby_parries(),"Gold is never caught by the expanded guard")
	collision.global_position=body.global_position
	for i in 3: await physics_frame
	box._physics_process(0)
	check(results==[int(CombatHitResult.Type.NORMAL_HIT)] and lan.combat_stats.health==90,"Rejected near gold still deals its real hit on actual overlap")
	box.deactivate()
	# Reproduce the report with real authored phase-two claws and physics callbacks.
	fresh()
	boss._enter_phase_2()
	boss.phase_2_buff_remaining=0
	boss.movement_direction=1
	boss.position=Vector2(0,555)
	boss.start_phase_2_body_action(&"master_phase2_pressure_five")
	boss._process(.70)
	var active_box: CombatHitbox2D = boss.phase_2_body_action.hitboxes.values()[0]
	var found := false
	lan.start_parry(true)
	lan.animated_sprite.pause()
	for x in range(0,351,2):
		lan.position=Vector2(x,555)
		var physical := false
		var catchable := false
		for shape: CollisionShape2D in active_box.get_children():
			if shape.disabled: continue
			physical=physical or shape.shape.collide(shape.global_transform,body.shape,body.global_transform)
			catchable=catchable or lan.can_catch_parry(active_box.attack,shape.shape,shape.global_transform)
		if not physical and catchable:
			found=true
			break
	check(found,"Found an authored phase-two claw that visually grazes but misses the body")
	results.clear()
	active_box.hit_resolved.connect(func(_target: Node,result: CombatHitResult.Type) -> void: results.append(int(result)))
	for i in 4: await physics_frame
	check(results==[int(CombatHitResult.Type.PARRY_SUCCESS)] and lan.combat_stats.health==100,"Actual phase-two physics now parries that grazing claw once")
	check(boss.parry_pause_remaining>0 and boss.combat_stats.poise==86,"Grazing parry uses shared hit-stop and poise feedback")
	boss._interrupt_phase_2_action(0)
	# Procedural flying swords use swept polygons rather than Area2D overlaps.
	boss.phase=1
	boss.manual_control=false
	var flying := MasterFlyingSwordCombat.new()
	flying.boss=boss
	for danger in [0,2]:
		fresh()
		lan.start_parry(true)
		var key := "catch_flying_%d" % danger
		var a := lan.global_position+Vector2(43,-50)
		var b := lan.global_position+Vector2(43,-8)
		flying.strike(key,a,b,a,b,danger==2)
		check(flying.settled.has(key)==(danger==0),"Only a parryable grazing flying sword can be caught")
		check(lan.combat_stats.health==100,"Flying-sword catch range cannot create extra damage")
	expect_save_untouched()
	finish("PARRY CATCH RANGE")

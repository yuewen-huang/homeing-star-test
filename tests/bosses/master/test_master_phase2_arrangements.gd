extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	var master: MasterBoss=room.get_node("MasterBoss")
	master.manual_control=true
	master.set_process(false)
	master._enter_phase_2()
	check(master.animated_sprite.scale==Vector2.ONE*master.PHASE_2_VISUAL_SCALE,"Transformation uses the same fixed body scale as phase two")
	master.animated_sprite.frame=7
	master._process(.001)
	check(master.animated_sprite.scale==Vector2.ONE*master.PHASE_2_VISUAL_SCALE,"Transformation never changes the sprite scale at its form boundary")
	master._enter_phase_2_idle(0)
	var frames:=master.animated_sprite.sprite_frames
	var idle_height:=frames.get_frame_texture(&"phase_2_idle",0).get_image().get_used_rect().size.y
	var upper_height:=frames.get_frame_texture(&"phase_2_uppercut",0).get_image().get_used_rect().size.y
	check(absi(upper_height-idle_height)<=1,"The static uppercut standing art matches idle body height")
	var expected := [5,5,6]
	for n in MasterPhase2BodyAction.IDS.size():
		for direction in [-1.0,1.0]:
			master.movement_direction=direction
			master.position.x=0
			master.phase_2_buff_remaining=0
			check(master.start_phase_2_body_action(MasterPhase2BodyAction.IDS[n]),"Phase-two combo callable in either facing")
			var action:=master.phase_2_body_action
			var groups: Dictionary={}
			var ticks:=0
			var body_only:=true
			var combat_source:=true
			var effect_indices: Dictionary={}
			var effects_match:=true
			var fixed_scale:=true
			var current_style := true
			while master.phase_2_body_action!=null and ticks<800:
				master._process(1.0/120.0)
				body_only=body_only and not master.wind_effect.visible
				fixed_scale=fixed_scale and master.animated_sprite.scale==Vector2.ONE*master.PHASE_2_VISUAL_SCALE
				if master.phase_2_body_action!=null:
					for effect_index: int in action.vfx.spawned: effect_indices[effect_index]=true
					for row: Dictionary in action.vfx.effects.values():
						if row.event.do=="slash":
							var claw: Node2D = row.effect.claw
							current_style = current_style and claw.look=="pixel" and is_equal_approx(claw.pixel,2.0) and is_equal_approx(claw.debris_size,.35)
							current_style = current_style and claw._material.shader.resource_path.ends_with("claw_mark.gdshader")
						if row.event.do=="slash" and row.event.has("claw_width"):
							effects_match=effects_match and is_equal_approx(float(row.effect.claw.width),float(row.event.claw_width))
						if row.event.do=="quake": effects_match=effects_match and is_equal_approx(float(row.effect.spec.width),float(row.event.width))
					for box: CombatHitbox2D in action.hitboxes.values():
						if box.monitoring:
							groups[box.attack.attack_id]=true
							combat_source=combat_source and box.attack.source==master
					ticks+=1
			check(ticks<800 and groups.size()==expected[n],"Authored claw hit groups play once, including shared cross claws")
			check(body_only and combat_source,"New actions use real combat data and keep retired painted wind hidden")
			check(effects_match and effect_indices.size()==(6 if n==1 else 5 if n==0 else 8),"All saved Studio effects spawn with the user's tuned thickness and range")
			check(fixed_scale,"All combo clips and idle handoffs keep one fixed body scale")
			check(current_style,"All production claws use the current Studio pixel renderer and fine debris")
			check(master.state==MasterBoss.State.PHASE_2_IDLE,"Combo returns to normal recovery")
			check(not action.active,"Finishing disables all gameplay collision immediately")
			await process_frame
	master.phase_2_buff_remaining=0
	master.phase_2_body_choice=0
	for id: StringName in MasterPhase2BodyAction.IDS:
		master._start_phase_2_regular_attack(100)
		check(master.phase_2_body_action.id==id,"Formal AI chooses the three new combos")
		master._interrupt_phase_2_action(.5)
		check(master.phase_2_body_action==null and master.state==MasterBoss.State.PHASE_2_IDLE,"Interruption clears body clock and collision")
	master.start_phase_2_body_action(MasterPhase2BodyAction.IDS[0])
	var held:=master.phase_2_body_action
	master.parry_pause_remaining=.1
	master._process(.02)
	check(is_zero_approx(held.elapsed),"Parry hit-stop freezes the body and gameplay timeline")
	master.parry_pause_remaining=0
	master.action_clock.extend_dodge_slow(1)
	master._process(.1)
	check(is_equal_approx(held.elapsed,.025),"Dodge slow motion uses the shared action clock")
	master.action_clock.clear()
	master._interrupt_phase_2_action(0)
	var lan: LanPlayer=room.get_node("Lan")
	lan.set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	lan.combat_stats.restore_health()
	master.start_phase_2_body_action(MasterPhase2BodyAction.IDS[0])
	master._process(.69)
	var box: CombatHitbox2D=master.phase_2_body_action.hitboxes.values()[0]
	var collision:=box.get_child(1) as CollisionShape2D
	var target_collision:=lan.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	lan.global_position+=collision.global_position-CombatHitQuery.shape_rect(target_collision).get_center()
	var resolved: Array=[]
	box.hit_resolved.connect(func(target: Node,result: CombatHitResult.Type)->void:resolved.append([target,result]))
	var initial_health:=lan.combat_stats.health
	for frame in 5: await physics_frame
	check(lan.combat_stats.health<initial_health and resolved.size()==1,"Multiple claw strands settle one real hit through the shared combat hitbox")
	for frame in 3: await physics_frame
	check(resolved.size()==1,"A retained multi-strand overlap cannot repeatedly damage the player")
	master._interrupt_phase_2_action(0)
	lan.global_position.y=master.global_position.y
	master.start_phase_2_body_action(MasterPhase2BodyAction.IDS[2])
	for tick in 378: master._process(1.0/120.0)
	var quake: Dictionary={}
	for row: Dictionary in master.phase_2_body_action.vfx.effects.values():
		if row.event.do=="quake": quake=row
	check(not quake.is_empty(),"Tuned quake spawns at the saved trigger time")
	lan.combat_stats.restore_health()
	lan.global_position=Vector2(quake.effect.global_position.x,master.global_position.y)
	master.manual_control=false
	var effects:=master.phase_2_body_action.vfx
	var point:=effects._ground_point(quake,lan.global_position)
	var arrival: float=quake.effect.arrival(point)
	var health:=lan.combat_stats.health
	effects._resolve_ground(quake,arrival-.01,arrival+.01)
	check(lan.combat_stats.health<health,"Procedural ground front settles real combat damage")
	health=lan.combat_stats.health
	effects._resolve_ground(quake,arrival,arrival+.02)
	check(lan.combat_stats.health==health,"One ground front cannot damage the same target twice")
	quake.hit_targets.clear()
	lan.global_position.y-=150
	effects._resolve_ground(quake,arrival-.01,arrival+.01)
	check(lan.combat_stats.health==health,"Jumping above the front avoids ground damage")
	master.manual_control=true
	master._interrupt_phase_2_action(0)
	master.phase_2_buff_remaining=master.PHASE_2_BUFF_DURATION
	master._start_phase_2_finale(100)
	check(master.phase_2_body_action.id==MasterPhase2BodyAction.IDS[2],"Buff finale uses the new body sequence")
	check(master.use_sobering_item() and master.phase_2_body_action==null and not master.phase_2_finale_active,"Sobering cancels the new finale")
	finish("MASTER PHASE TWO ARRANGEMENTS")

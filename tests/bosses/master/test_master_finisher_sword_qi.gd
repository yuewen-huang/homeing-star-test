extends "../../support/harness.gd"
var master: MasterBoss
var lan: LanPlayer
var results: Array[int]=[]

func fresh(move: StringName, direction := 1.0) -> MasterPhase1Action:
	master._cancel_phase_1_action()
	master.phase=1
	master.manual_control=true
	master.position=Vector2(0,555)
	master.movement_direction=direction
	master.combat_stats.restore_health()
	master.combat_stats.restore_poise()
	master.poise_broken=false
	master.parry_pause_remaining=0
	master.red_parry_hold=false
	master.action_clock.clear()
	lan.reset_after_map_fall(Vector2(2200,555))
	lan.combat_stats.restore_health()
	lan.parry_chain.cancel()
	results.clear()
	master.start_phase_1_action(move)
	return master.phase_1_action

func meet(qi: MasterGreatbladeSwordQi, time: float) -> void:
	var transform := qi.Blade.pose(qi.effect.spec,time)
	var point := transform*qi.Blade.blade_point(qi.effect.spec,.60,.88)
	lan.global_position=qi.to_global(point)+Vector2(0,29)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	master=room.get_node("MasterBoss")
	lan=room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	master.attack_hitbox.hit_resolved.connect(func(_target: Node,result: CombatHitResult.Type)->void:results.append(int(result)))
	await physics_frame
	for move: StringName in [&"combo_four",&"combo_five"]:
		for direction in [-1.0,1.0]:
			var action := fresh(move,direction)
			var cut: Dictionary=action.timeline.cuts[-1]
			var start := float(cut.release)-float(cut.wind_time)
			action.advance(start-.001)
			check(action.sword_qi==null,"Earlier cuts never spawn final qi: "+move)
			action.advance(.002)
			var qi := action.sword_qi as MasterGreatbladeSwordQi
			check(qi!=null and qi.effect.spec.gb_motion==("hinge" if move==&"combo_four" else "plunge"),"Four uses hinge; five uses a rigid guillotine: "+move)
			check(is_equal_approx(qi.starts_at+qi.Profile.impact_time(qi.effect.spec),float(cut.contact_at)),"Qi lands on the measured last-cut contact, without retiming the body")
			check(qi.attack==action._attack_for_cut(action._qi_cut) and qi.attack.danger_type==CombatAttackData.DangerType.NORMAL,"Final body and qi share one normal parryable attack")
			check(qi.effect.spec.gb_opacity==.62 and qi.effect.style=="real","Production uses the approved translucent metal look")
			var saved: Dictionary=qi.Ground.normalized(qi.studio_profile("hinge" if move==&"combo_four" else "plunge").event)
			var synced: bool=qi.effect.spec.gb_surface==saved.gb_surface
			for key in ["gb_opacity","gb_hold","gb_fade","gb_echo","debris_density","debris_height","dust_density","dust_height","dust_spread"]:
				synced=synced and is_equal_approx(float(qi.effect.spec[key]),float(saved[key]))
			check(synced,"Saved surface, fading, debris and dust parameters reach the actual final attack")
			var landed := qi.Blade.pose(qi.effect.spec,qi.Profile.impact_time(qi.effect.spec))
			var blade_start := qi.to_global(landed*qi.Blade.blade_point(qi.effect.spec,0,1))
			var blade_end := qi.to_global(landed*qi.Blade.blade_point(qi.effect.spec,1,1))
			check(blade_start.distance_to(blade_end)>700,"Enlarged production blade spans over 700 world pixels in either facing")
			var fall := float(qi.effect.spec.gb_charge)+float(qi.effect.spec.gb_pause)
			var impact := qi.Profile.impact_time(qi.effect.spec)
			check(qi.blade_shapes(0,fall-.001).is_empty() and qi.blade_shapes(impact+.01,impact+.1).is_empty(),"Hovering sword, held sword and tails never hit")
			var time := lerpf(fall,impact,.85)
			check(not qi.blade_shapes(time-.001,time).is_empty(),"The currently falling bevel supplies live collision")
			meet(qi,time)
			qi.advance(time-float(qi.effect.age))
			check(results.is_empty() and lan.combat_stats.health==100,"Development preview remains harmless")
			master.manual_control=false
			lan.start_parry(true)
			qi._resolve(time-.001,time)
			check(results==[int(CombatHitResult.Type.PARRY_SUCCESS)] and lan.combat_stats.health==100,"Actual blade geometry resolves one shared parry in either facing")
			qi._resolve(time-.001,time)
			check(results.size()==1,"Retained qi cannot parry or damage the same target twice")
			check(master.combat_stats.poise==master.combat_stats.max_poise-CombatTuning.BOSS_NORMAL_PARRY_POISE,"Parry settles shared boss poise once")
			master.manual_control=true
			master.parry_pause_remaining=0
			action.advance(float(cut.contact_at)-action.elapsed+.001)
			check(qi==action.sword_qi and master.attack_hitbox.hit_targets.has(lan.get_instance_id()),"The body inherits qi settlement when its final hitbox opens")
		var action := fresh(move)
		var cut: Dictionary=action.timeline.cuts[-1]
		action.advance(float(cut.release)+.01)
		var qi := action.sword_qi as MasterGreatbladeSwordQi
		var time := qi.Profile.impact_time(qi.effect.spec)-.005
		master.attack_hitbox.hit_targets[lan.get_instance_id()]=true
		master.manual_control=false
		meet(qi,time)
		qi._resolve(time-.001,time)
		check(results.is_empty(),"A target already struck by the physical final blade cannot take qi damage")
		action=fresh(move)
		action.advance(float(action.timeline.cuts[-1].release))
		qi=action.sword_qi
		var age: float=qi.effect.age
		master.parry_pause_remaining=.1
		master._process(.01)
		check(is_equal_approx(qi.effect.age,age),"Parry stop freezes blade and body together")
		master.parry_pause_remaining=0
		master.action_clock.extend_dodge_slow(1)
		master._process(.1)
		check(is_equal_approx(qi.effect.age-age,.025),"Qi uses the production dodge action clock")
		master.action_clock.clear()
		action.advance(action.timeline.duration-action.elapsed+.01)
		check(qi.tail_only and qi.get_parent()==master,"Recovery keeps only a harmless visual tail")
		qi.set_process(false)
		master._enter_phase_2()
		check(not qi.active and not qi.visible,"Phase handoff clears surviving final qi")
	for move: StringName in [&"horizontal",&"vertical",&"combo_three",&"rise_unbalance"]:
		var action := fresh(move)
		action.advance(action.timeline.duration-.01)
		check(action.sword_qi==null,"Other phase-one moves retain their original effects: "+move)
	room.free()
	current_scene=null
	expect_save_untouched()
	finish("MASTER FINISHER SWORD QI")

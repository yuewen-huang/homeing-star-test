extends "../../../support/harness.gd"
const SINGLES := preload("res://scripts/bosses/opera_dancer/opera_single_moves.gd")
const CITY := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")

func run() -> void:
	use_memory_progress()
	var city: SunkenCavern = CITY.instantiate()
	root.add_child(city)
	current_scene = city
	await wait_frames(5)
	var stage = city.gate_stage
	var p := city.player
	var entry: Vector2 = city.to_local(stage.to_global(Vector2(1000,669)))
	p.reset_after_map_fall(entry)
	city.snap_camera()
	for i in 12: await physics_frame
	var actor = stage.dancer
	var spawn: Vector2 = city.to_local(stage.get_node("OperaDancer").global_position)
	var trio = actor.singles.trio
	for move in range(SINGLES.Move.RICOCHET,SINGLES.Move.ULTIMATE+1):
		p.reset_after_map_fall(entry)
		p.combat_stats.restore_health()
		actor.reset(spawn,true)
		actor.training = move+1
		actor.begin_single(move)
		var damages := {}
		var animations := {}
		var pogo := false
		var took_damage := false
		var safe_handles := false
		var concealed := false
		var damage_free_end := 0.0
		var measured_cage := false
		for tick in 730:
			await physics_frame
			took_damage = took_damage or p.combat_stats.health < p.combat_stats.max_health
			if actor.singles.move != move: break
			for id in trio.hits: damages[id] = true
			if move == SINGLES.Move.BIND and not measured_cage and trio.age >= trio.cage.CAGED:
				var left: Vector2 = trio.props[0].position
				var right: Vector2 = trio.props[1].position
				var top: Vector2 = trio.props[2].position
				check(is_equal_approx(right.x-left.x,260) and is_equal_approx(left.y,right.y), "low umbrellas flank the player at ground level")
				check(is_equal_approx(top.x,(left.x+right.x)/2) and top.y < left.y-140, "third umbrella stays overhead")
				measured_cage = true
			for prop in trio.props:
				pogo = pogo or prop.plate.collision_layer>0
			animations[actor.animated_sprite.animation] = true
			concealed = concealed or actor.invulnerable
			if move==SINGLES.Move.ULTIMATE and trio.props[2].plate.collision_layer > 0:
				if trio.hits.is_empty(): damage_free_end += 1.0/60
				safe_handles = safe_handles or trio.props[0].plate.collision_layer>0
		check(actor.singles.move == -1 and not actor.invulnerable and trio.hits.is_empty(), "move %d ends and cleans up"%move)
		match move:
			SINGLES.Move.RICOCHET: check(damages.size()==3 and took_damage and pogo,"three cone passes hit and reopen for downslash")
			SINGLES.Move.BIND: check(pogo and damages.has("silk0_0") and damages.has("silk1_0") and damages.has("silk2_0") and damages.has("pincer2") and damages.has("cage_impact"),"three weaves, rebound surfaces and final pincer")
			SINGLES.Move.MIRAGE: check(concealed and animations.has(&"spin") and animations.has(&"double_vertical") and damages.size()==6,"mirage double lift, spin and three crosses")
			SINGLES.Move.STAIRS: check(pogo and damages.has("dive") and damages.has("kick0"),"stairs have real pogo surfaces, kicks and dive")
			SINGLES.Move.ULTIMATE: check(safe_handles and damage_free_end>0.8 and damages.size()>=24,"needles, stakes, ground waves and safe recovery")
	for move in [SINGLES.Move.RICOCHET,SINGLES.Move.BIND,SINGLES.Move.MIRAGE]:
		p.reset_after_map_fall(entry)
		p.combat_stats.restore_health()
		actor.reset(spawn,true)
		actor.training = move+1
		actor.begin_single(move)
		var tried := false
		var broken := false
		var parried_sleeves: Array[StringName] = []
		var record_sleeve := func(attack: CombatAttackData, _chain: bool):
			if String(attack.attack_id).begins_with("opera_9_"): parried_sleeves.append(attack.attack_id)
		p.parry_resolved.connect(record_sleeve)
		var resumed_spin := false
		var resumed_crosses := false
		for tick in (720 if move == SINGLES.Move.MIRAGE else 360):
			await physics_frame
			if move == SINGLES.Move.RICOCHET and p.red_parry_source == actor:
				broken = p.pulse_duel.boss_internal_hp > 0 and actor.red_parry_hold and actor.singles.move == -1
			if actor.singles.move!=move: break
			if move==SINGLES.Move.RICOCHET and trio.age>=1.32 and not tried:
				p.facing_direction = signf(trio.props[0].global_position.x-p.global_position.x)
				p.start_parry()
				tried = true
			elif move==SINGLES.Move.BIND and trio.age>=2.84 and not tried:
				p.start_parry()
				tried = true
			elif move==SINGLES.Move.MIRAGE and trio.age>=2.13 and not tried:
				p.facing_direction = -trio.ambush_facing
				p.start_parry()
				tried = true
			if trio.broken_at>=0: broken = true
			if move == SINGLES.Move.MIRAGE and not parried_sleeves.is_empty():
				resumed_spin = resumed_spin or actor.animated_sprite.animation == &"spin"
				resumed_crosses = resumed_crosses or trio.hits.has("cross0_0")
		p.parry_resolved.disconnect(record_sleeve)
		if move == SINGLES.Move.MIRAGE:
			check(not parried_sleeves.is_empty() and resumed_spin and resumed_crosses and not broken,"parried ambush continues into spin and closing crosses")
		else:
			check(broken,"real combat counter %d"%move)
		if move==SINGLES.Move.BIND:
			var maximum: int = actor.combat_stats.max_health
			check(actor.combat_stats.health == maximum and p.pulse_duel.boss_internal_hp > 0, "breaking the cage stores injury for the burst")
		if move==SINGLES.Move.RICOCHET:
			check(actor.combat_stats.health == actor.combat_stats.max_health, "manual red counter stores injury without HP damage")
			for tick in 120:
				if not actor.red_parry_hold: break
				await physics_frame
			check(not actor.red_parry_hold, "dancer resumes after the red counter finishes")
	p.reset_after_map_fall(entry)
	actor.reset(spawn,true)
	actor.training = SINGLES.Move.STAIRS + 1
	actor.begin_single(SINGLES.Move.STAIRS)
	var struck_at_apex := false
	var blocked_dive := false
	var landed := false
	for frame in 350:
		await physics_frame
		if actor.singles.move != SINGLES.Move.STAIRS: break
		if not struck_at_apex and trio.age > 3.10:
			p.global_position = actor.global_position
			var previous_hp: int = actor.combat_stats.health
			actor.receive_hit(1, p.global_position)
			struck_at_apex = actor.combat_stats.health < previous_hp
		if not blocked_dive and trio.hits.has("dive"):
			var box: CombatHitbox2D = trio.hits.dive.box
			if box.attack != null:
				var torso := p.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
				p.global_position += box.global_position - torso.global_position
				p.start_parry()
				blocked_dive = box.resolve_nearby_parries()
		landed = landed or trio.marks.has("land")
	check(struck_at_apex and blocked_dive and landed and trio.broken_at < 0, "Airborne hit and ordinary dive parry both preserve the landing")
	p.reset_after_map_fall(entry)
	actor.reset(spawn,true)
	actor.begin(1)
	actor._throw_parasol()
	var parried_outbound := false
	var armed_return := false
	for frame in 420:
		await physics_frame
		if actor.beat == actor.Beat.OUT and not parried_outbound:
			var torso := p.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
			p.global_position += actor.parasol.hitbox.global_position - torso.global_position
			p.start_parry()
			parried_outbound = actor.parasol.hitbox.resolve_nearby_parries()
		if actor.beat == actor.Beat.BACK and actor.parasol.hitbox.attack != null:
			armed_return = true
		if actor.beat == actor.Beat.CATCH: break
	check(parried_outbound and armed_return and actor.beat == actor.Beat.CATCH, "Parried rehearsal umbrella still attacks on return and reaches the dancer")
	actor.reset(spawn,true)
	actor.training = 0
	actor.combat_stats.set_health_ratio(0.49)
	var skill: int = actor.choose_single()
	actor.begin_single(skill)
	var followup: int = actor.choose_single()
	actor.begin_single(followup)
	check(skill==SINGLES.Move.MOON and followup==SINGLES.Move.ULTIMATE and actor.choose_single() not in [SINGLES.Move.MOON,SINGLES.Move.ULTIMATE],"half health garden then super, once each")
	city.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("PARASOL TRIOS")

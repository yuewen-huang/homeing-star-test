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
		var safe_handles := false
		var concealed := false
		var damage_free_end := 0.0
		for tick in 730:
			await physics_frame
			if actor.singles.move != move: break
			for id in trio.hits: damages[id] = true
			for prop in trio.props:
				pogo = pogo or prop.plate.collision_layer>0
			animations[actor.animated_sprite.animation] = true
			concealed = concealed or actor.invulnerable
			if move==SINGLES.Move.ULTIMATE and trio.age>4.95 and trio.age<6.0:
				if trio.hits.is_empty(): damage_free_end += 1.0/60
				safe_handles = safe_handles or trio.props[0].plate.collision_layer>0
		check(actor.singles.move == -1 and not actor.invulnerable and trio.hits.is_empty(), "move %d ends and cleans up"%move)
		match move:
			SINGLES.Move.RICOCHET: check(damages.size()==3 and p.combat_stats.health<100,"three aimed cone passes have actual contact")
			SINGLES.Move.BIND: check(pogo and damages.size()>=25,"bind soft tell, rebound and cutting ring")
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
		for tick in 360:
			await physics_frame
			if actor.singles.move!=move: break
			if move==SINGLES.Move.RICOCHET and trio.age>=1.32 and not tried:
				p.facing_direction = signf(trio.props[0].global_position.x-p.global_position.x)
				p.start_parry()
				tried = true
			elif move==SINGLES.Move.BIND and trio.age>0.74 and not tried:
				p.global_position = actor.global_position+Vector2(-55,0)
				p.start_attack_1x(1)
				tried = true
			elif move==SINGLES.Move.MIRAGE and trio.age>0.86 and not tried:
				var x: float = trio.points[trio.sites[0]].x
				p.global_position = trio.to_global(Vector2(x+200,0))
				if trio.age>1.42:
					p.facing_direction = -1
					p.start_parry()
					tried = true
			if trio.broken_at>=0: broken = true
		check(broken,"real combat counter %d"%move)
		if move==SINGLES.Move.RICOCHET:
			check(actor.combat_stats.health==434,"only the returned cone damages the dancer")
	actor.reset(spawn,true)
	actor.training = 0
	actor.combat_stats.set_health_ratio(0.49)
	var skill: int = actor.choose_single()
	actor.begin_single(skill)
	check(skill==SINGLES.Move.ULTIMATE and actor.choose_single()!=SINGLES.Move.ULTIMATE,"half health super once")
	city.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("PARASOL TRIOS")

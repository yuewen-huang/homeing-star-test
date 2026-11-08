extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)
func fixture(boss_x: float,player_x: float) -> BossDevelopmentRoom:
	var room: BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	room.select_combo(3)
	room.set_combat_simulation(true)
	room.player.position=Vector2(player_x,room.FLOOR_Y)
	room.adapter.boss._on_ambush_finished(Vector2(boss_x,room.FLOOR_Y))
	return room
func run() -> void:
	for spec in [[900,380,"left"],[180,850,"right"],[1050,1190,"wall"],[900,380,"cross"],[900,380,"reset"],[900,380,"defeat"]]:
		var room:=fixture(spec[0],spec[1])
		var actor: SandstormFighter=room.adapter.boss
		var saw_step:=false
		var saw_melee:=false
		var crossed:=false
		var clean:=true
		var previous:=Vector2.ZERO
		var abort:=false
		for tick in 480:
			await physics_frame
			if is_instance_valid(actor.approach):
				var step: Node2D=actor.approach
				clean=clean and actor.attack_hitbox==null and absf(step.global_position.y-room.FLOOR_Y)<.01
				clean=clean and absf(actor.body_spacing_rect().get_center().x-step.global_position.x)<.01
				if saw_step: clean=clean and absf(step.global_position.x-previous.x)<26
				previous=step.global_position
				saw_step=true
				if spec[2]=="cross" and step.elapsed>.2 and not crossed:
					# Engineering fixture only; visual playtest uses ordinary inputs separately.
					room.player.position.x=step.origin.x-step.facing*100
					crossed=true
				if spec[2] in ["reset","defeat"]:
					if spec[2]=="reset": actor.set_combat_enabled(false)
					else: actor.receive_hit(999,Vector2.ZERO)
					abort=true
					break
			if is_instance_valid(actor.melee): saw_melee=true
			if saw_melee and actor.looping_idle:
				check(actor._skill_wait>=.80,"Melee punish window missing: "+spec[2])
				actor.set_counter_progress(6)
				check(actor.can_offer_break_empower(),"Six-parry reward blocked during recovery: "+spec[2])
				break
			if crossed and actor.looping_idle:
				check(not saw_melee,"Immediate turn-hit after crossing")
				break
		if abort:
			for tick in 100: await physics_frame
			check(not is_instance_valid(actor.approach) and not actor._melee_due and not is_instance_valid(actor.melee),"Pursuit survived "+spec[2])
		elif not crossed: check(saw_melee,"No follow-up melee: "+spec[2])
		check(clean,"Step drift, jump or damaging hitbox: "+spec[2])
		check(saw_step or spec[2]=="wall","No approach: "+spec[2])
		print("PRESSURE CASE ",spec[2]," step=",saw_step," melee=",saw_melee)
		room.free()
		await process_frame
	var room:=fixture(820,380)
	var actor: SandstormFighter=room.adapter.boss
	actor.play_thomas()
	var overlap:=false
	var saw_waves:=false
	var approached:=false
	for tick in 1100:
		await physics_frame
		if is_instance_valid(actor.thomas):
			saw_waves=saw_waves or not actor.thomas.waves.is_empty()
			overlap=overlap or (not actor.thomas.waves.is_empty() and (is_instance_valid(actor.approach) or is_instance_valid(actor.melee)))
		if is_instance_valid(actor.approach) or is_instance_valid(actor.melee):
			approached=true
			break
	check(saw_waves and approached and not overlap,"Thomas waves overlapped new pursuit or no pursuit")
	room.free()
	print("SANDSTORM PRESSURE AI: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

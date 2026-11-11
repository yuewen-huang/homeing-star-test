extends "../../support/harness.gd"
const MOTOR := preload("res://scripts/player/lan/lan_fast_fall.gd")
const PLAYER := preload("res://scenes/player/lan/lan_player.tscn")
var p: LanPlayer
var world: Node2D
var targets: Array[Receiver] = []
var output := "res://../homeing-star-test/artifacts/lan_fast_fall_20261104"

class Receiver extends DamageReceiver2D:
	var hits:=0
	var damage:=0
	var poise:=0
	var shielded:=false
	func receive_attack_hit(hit: RefCounted, _at: Vector2) -> void:
		if shielded: return
		hits+=1
		damage+=hit.health_damage
		poise+=hit.poise_damage
	func receive_hit(_damage: int,_at: Vector2) -> void:
		assert(false,"Fast fall must use the shared normal-hit context")

func step(n: int) -> void:
	for i in n: await physics_frame

func set_plunge(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_X
	key.pressed = pressed
	Input.parse_input_event(key)

func set_attack(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = pressed
	Input.parse_input_event(key)
	Input.flush_buffered_events()

func release() -> void:
	set_plunge(false)
	set_attack(false)
	for action in [&"jump",&"ui_down",&"ui_left",&"ui_right",&"instant_dash"]: Input.action_release(action)

func reset(height: float) -> void:
	release()
	p.reset_after_map_fall(Vector2(600,600))
	await step(25)
	p.reset_after_map_fall(Vector2(600,600-height))
	p.air_state=p.AirState.FALLING
	p.play_air_animation(&"fall")
	for target in targets:
		target.hits=0
		target.damage=0
		target.poise=0

func trigger() -> void:
	set_plunge(true)
	await step(2)
	set_plunge(false)

func land() -> void:
	for i in 160:
		await step(1)
		if p.air_state==p.AirState.GROUNDED: return
	check(false,"Fast fall reached a real landing")

func receiver(at: Vector2, duplicate:=false) -> Receiver:
	var target:=Receiver.new()
	target.position=at
	for i in (2 if duplicate else 1):
		var area:=Area2D.new()
		area.collision_layer=2
		area.collision_mask=0
		area.add_to_group(&"hurtbox")
		var collision:=CollisionShape2D.new()
		var shape:=RectangleShape2D.new()
		shape.size=Vector2(12,32)
		collision.shape=shape
		collision.position.y=-16
		area.add_child(collision)
		target.add_child(area)
	world.add_child(target)
	targets.append(target)
	return target

func rock(rect: Rect2) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.collision_layer=1
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=rect.size
	collision.shape=shape
	collision.position=rect.get_center()
	body.add_child(collision)
	world.add_child(body)
	return body

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	use_memory_progress()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world=Node2D.new()
	root.add_child(world)
	current_scene=world
	RenderingServer.set_default_clear_color(Color("17252e"))
	rock(Rect2(0,600,1280,100))
	var art:=Polygon2D.new()
	art.polygon=PackedVector2Array([Vector2(0,600),Vector2(1280,600),Vector2(1280,720),Vector2(0,720)])
	art.color=Color("354950")
	world.add_child(art)
	p=PLAYER.instantiate()
	p.position=Vector2(600,600)
	p.fallback_ground_y=600
	p.world_min_x=0
	p.world_max_x=1280
	world.add_child(p)
	var near:=receiver(Vector2(640,600),true)
	var far:=receiver(Vector2(750,600))
	var shield:=receiver(Vector2(560,600))
	shield.shielded=true
	await step(3)
	check(MOTOR.damage(100)==0,"Threshold and lower have no damage")
	check(MOTOR.damage(101)>=2 and MOTOR.damage(101)<=3,"Just above threshold deals roughly one-quarter normal damage")
	check(MOTOR.damage(400)==5 and MOTOR.damage(2000)==5,"High-drop damage caps at half the first cut")
	for height in [80.0,100.0,220.0,500.0]:
		await reset(height)
		await trigger()
		check(p.attack_state==p.AttackState.FAST_FALL and p.velocity.y>0,"X starts the ground plunge at height %.0f" % height)
		check(not p.is_invulnerable() and not p.can_start_double_jump() and not p.can_start_aerial_dash(),"Fast fall grants no invulnerability or aerial cancel")
		check(near.hits==0,"No midair hit before contact")
		await capture("fall_%.0f" % height)
		await land()
		check(p.animated_sprite.animation==MOTOR.BODY_LAND,"Third-finisher landing body is reused")
		check(absf(p.fast_fall.last_height-height)<2,"Height is measured from trigger to actual floor")
		if height<=100:
			check(p.fast_fall.last_damage==0 and near.hits==0 and get_nodes_in_group(&"lan_fast_fall_fx").is_empty(),"Low drop has body only, no damage, wave or smoke")
		else:
			check(near.hits==1 and near.damage==MOTOR.damage(p.fast_fall.last_height) and near.poise==1,"Touchdown settles one modest hit despite two hurtboxes")
			check(far.hits==0 and shield.hits==0,"Out-of-range and shielded targets take no damage")
			check(get_nodes_in_group(&"lan_fast_fall_fx").size()==2,"High touchdown emits one wave and one smoke sheet")
		await step(3)
		await capture("land_%.0f" % height)
		var hits:=near.hits
		await step(12)
		check(near.hits==hits,"Lingering visuals cannot hit again")
	# A finite authored platform intercepts the descent before the lower floor.
	await reset(300)
	p.register_ground_surface(Rect2(500,380,200,10))
	await trigger()
	await land()
	check(absf(p.position.y-380)<1 and p.fast_fall.last_height<100 and p.fast_fall.last_damage==0,"Intermediate platform uses its actual 80px drop, not the distant floor")
	p.ground_surfaces.clear()
	# Real collision also intercepts a fast descent without authored snap surfaces.
	var platform:=rock(Rect2(500,380,200,12))
	await reset(300)
	await trigger()
	await land()
	check(absf(p.position.y-380)<2 and p.fast_fall.last_damage==0,"Physical platform catches the descent without tunnelling")
	platform.queue_free()
	await step(2)
	var wall:=rock(Rect2(618,520,8,80))
	await reset(250)
	await trigger()
	await land()
	check(near.hits==0,"Ground burst cannot hit through a solid wall")
	wall.queue_free()
	await step(2)
	# Releasing control is allowed immediately after ground contact.
	for next in ["jump","attack","dodge","parry"]:
		await reset(220)
		await trigger()
		await land()
		if next=="jump": Input.action_press(&"jump")
		else: p.update_combat_input_buffers(0,true if next=="attack" else false,next=="dodge",next=="parry")
		await step(2)
		var ok:=false
		match next:
			"jump": ok=p.velocity.y<0
			"attack": ok=p.attack_state==p.AttackState.ATTACK_1X
			"dodge": ok=p.ground_action_state==p.GroundActionState.BACK_DODGE
			"parry": ok=p.defense_state!=p.DefenseState.NONE
		check(ok,"Landing immediately accepts "+next)
	await reset(250)
	p.start_jump_attack_1x()
	check(not p.fast_fall.can_start(p),"Cannot steal an active air attack")
	await reset(250)
	p.start_aerial_dash(1)
	check(not p.fast_fall.can_start(p),"Cannot steal an active air dash")
	await reset(250)
	await trigger()
	p.set_input_frozen(true)
	await step(5)
	p.set_input_frozen(false)
	await step(90)
	check(near.hits==0 and p.attack_state!=p.AttackState.FAST_FALL,"Freeze interrupts the fall without a delayed burst")
	await reset(250)
	await trigger()
	p.reset_after_map_fall(Vector2(600,600))
	await step(30)
	check(near.hits==0 and p.attack_state==p.AttackState.NONE,"Respawn cannot retain a pending fast-fall hit")
	# Deep water cancels the action into the existing entry motor, not a ground hit.
	var water:=UnderwaterVolume.new()
	water.position=Vector2(400,350)
	water.size=Vector2(400,300)
	world.add_child(water)
	water.register_to(p)
	await reset(350)
	await trigger()
	var entered:=false
	for i in 60:
		await step(1)
		if p.air_state==p.AirState.SWIMMING:
			entered=true
			break
	check(entered and p.attack_state==p.AttackState.NONE,"Fast fall into water becomes normal swimming")
	check(near.hits==0 and get_nodes_in_group(&"lan_fast_fall_fx").is_empty(),"Water entry makes no ground damage, wave or smoke")
	check(not p.fast_fall.can_start(p),"Swimming cannot trigger ground fast fall")
	set_plunge(true)
	await step(2)
	check(p.air_state==p.AirState.SWIMMING and p.attack_state==p.AttackState.NONE,"X cannot plunge while swimming")
	set_plunge(false)
	water.queue_free()
	await step(3)
	await reset(250)
	p.hit_reaction_active=true
	check(not p.fast_fall.can_start(p),"Hit reaction cannot be cancelled into fast fall")
	p.hit_reaction_active=false
	await reset(250)
	await land()
	set_plunge(true)
	await step(2)
	check(p.air_state==p.AirState.GROUNDED and p.attack_state!=p.AttackState.FAST_FALL,"Ground X does not start a plunge")
	await reset(250)
	await land()
	Input.action_press(&"jump")
	await step(2)
	var was_rising := p.air_state==p.AirState.RISING and p.velocity.y<0
	Input.action_release(&"jump")
	await trigger()
	check(was_rising and p.attack_state==p.AttackState.FAST_FALL and p.velocity.y>0,"X reverses an active jump into a plunge")
	await reset(250)
	Input.action_press(&"ui_down")
	await step(2)
	check(p.attack_state==p.AttackState.NONE,"Holding down alone preserves the airborne state")
	# Compare the same arc and horizontal input with and without the slash.
	var baseline: Array[Vector2] = []
	for swing in [false, true]:
		await reset(250)
		Input.action_press(&"ui_right")
		Input.action_press(&"ui_down")
		await step(4)
		var jump_used := p.double_jump_used
		if swing: set_attack(true)
		await step(2)
		baseline.append(p.position)
		baseline.append(p.velocity)
		check(p.attack_state == p.AttackState.NONE and p.double_jump_used == jump_used,
			"Holding down and a whiff preserve air control and the double jump")
		if swing:
			check(p.fast_fall.swing_recovery > 0.0 and p.fast_fall.last_contacts == 0,
				"Down+attack swings once in empty air")
			set_attack(false)
	check(baseline[0].is_equal_approx(baseline[2]) and baseline[1].is_equal_approx(baseline[3]),
		"Whiffing the downward swing preserves the exact position and velocity of the normal arc")
	await reset(250)
	var nearby := receiver(p.position + Vector2(0.0, 28.0), true)
	Input.action_press(&"ui_down")
	set_attack(true)
	await step(2)
	set_attack(false)
	check(nearby.hits == 1 and p.velocity.y < 0.0 and p.fast_fall.last_contacts == 1,
		"Down+attack hits an enemy directly below on the first swing and rebounds")
	targets.erase(nearby)
	nearby.queue_free()
	await reset(250)
	var foothold := receiver(Vector2(600,440), true)
	set_plunge(true)
	for i in 20:
		await step(1)
		if foothold.hits > 0: break
	check(foothold.hits == 1 and p.velocity.y < 0, "Swept downslash hits enemy once and bounces before landing")
	check(p.can_start_double_jump() and not p.has_buffered_attack(), "Bounce restores double jump and consumes attack input")
	check(not p.is_invulnerable(), "Bounce grants no invulnerability")
	await step(4)
	check(p.attack_state==p.AttackState.NONE and foothold.hits==1,"Holding X after a bounce does not trigger another plunge")
	set_plunge(false)
	await capture("downslash_bounce")
	# Spend the bounce refill, then chain a wall jump without landing.
	p.start_double_jump()
	check(p.double_jump_used, "Double jump spends the downslash refill")
	p.aerial_dash_used = true
	p.wall_slide_normal_x = -1.0
	p.start_wall_slide()
	check(p.double_jump_used, "Wall contact alone does not refill double jump")
	var stamina_before_wall := p.combat_stats.stamina
	p.start_wall_jump()
	check(p.velocity.y < 0 and p.can_start_double_jump(), "Wall jump restores double jump after a downslash chain")
	check(p.aerial_dash_used and p.combat_stats.stamina == stamina_before_wall, "Wall jump preserves spent dash and does not refund stamina")
	p.start_double_jump()
	check(p.double_jump_used and not p.can_start_double_jump(), "Wall refill gives exactly one extra jump")
	foothold.queue_free()
	targets.erase(foothold)
	await step(2)
	await reset(250)
	var pad := rock(Rect2(580,430,40,10))
	pad.add_to_group(&"pogo_target")
	await trigger()
	for i in 20:
		await step(1)
		if p.attack_state == p.AttackState.NONE: break
	check(p.velocity.y < 0 and p.can_start_double_jump(), "Explicit solid pogo target bounces and refreshes")
	pad.queue_free()
	await step(2)
	await reset(250)
	var armored := receiver(Vector2(600,440))
	armored.shielded = true
	await trigger()
	for i in 20:
		await step(1)
		if p.attack_state == p.AttackState.NONE: break
	check(p.velocity.y < 0 and armored.hits == 0, "Protected targets allow foothold without bypassing their damage immunity")
	armored.queue_free()
	targets.erase(armored)
	await step(2)
	await reset(250)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	await step(2)
	check(p.attack_state == p.AttackState.JUMP_ATTACK_1X, "J without down retains ordinary aerial attack")
	check(p.get_node("StateTrace").report_count==0,"No animation-owner contradictions")
	release()
	expect_save_untouched()
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	world.queue_free()
	await wait_frames(8)
	finish("LAN FAST FALL")

extends "../../support/harness.gd"
var player: LanPlayer
var world: Node2D

func step(count: int) -> void:
	for i in count: await physics_frame

func release() -> void:
	for action in [&"ui_right",&"ui_left",&"jump",&"instant_dash"]: Input.action_release(action)

func reset() -> void:
	release()
	player.ground_surfaces.clear()
	player.reset_after_map_fall(Vector2(0,1000))
	await step(3)

func jump_height(hold_frames: int, second_jump: bool = false) -> float:
	await reset()
	if second_jump:
		Input.action_press(&"jump")
		await step(20)
		Input.action_release(&"jump")
		await step(2)
	var start_y := player.position.y
	Input.action_press(&"jump")
	var top := player.position.y
	for i in 90:
		if i==hold_frames: Input.action_release(&"jump")
		await step(1)
		top=minf(top,player.position.y)
	return start_y-top

func run() -> void:
	var progress := use_memory_progress()
	world=Node2D.new()
	root.add_child(world)
	current_scene=world
	player=load("res://scenes/player/lan/lan_player.tscn").instantiate()
	player.world_min_x=-5000
	player.world_max_x=5000
	player.fallback_ground_y=1000
	player.position=Vector2(0,1000)
	world.add_child(player)
	await step(3)
	var short_height:=await jump_height(3)
	var full_height:=await jump_height(65)
	print("JUMP HEIGHTS short=",short_height," full=",full_height)
	check(absf(short_height-full_height)<0.1,"Tap and held jump reach the same height")
	check(full_height>95 and full_height<105,"Held jump preserves existing maximum reach")
	var short_double:=await jump_height(3,true)
	var full_double:=await jump_height(65,true)
	print("DOUBLE JUMP HEIGHTS tap=",short_double," held=",full_double)
	check(absf(short_double-full_double)<0.1,"Tap and held second jump reach the same height")
	check(full_double>95 and full_double<105,"Second jump preserves existing maximum reach")
	await reset()
	Input.action_press(&"jump")
	await step(12)
	Input.action_press(&"ui_right")
	await step(8)
	check(player.attack_state==LanPlayer.AttackState.NONE and not player.aerial_dash_used and player.velocity.x>0,"Air steering does not spend dash")
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(8)
	check(player.velocity.x<0 and not player.aerial_dash_used,"Air reversal steers promptly without bursting")
	progress.locked.append(SaveProgressService.ABILITY_DASH)
	Input.action_press(&"instant_dash")
	await step(3)
	check(player.attack_state==LanPlayer.AttackState.AERIAL_DASH and player.aerial_dash_used,"U triggers air dash without changing its existing unlock")
	progress.locked.clear()
	Input.action_release(&"instant_dash")
	await step(30)
	Input.action_press(&"instant_dash")
	await step(3)
	check(player.attack_state!=LanPlayer.AttackState.AERIAL_DASH,"Second air dash cannot bypass the one-per-flight budget")
	await reset()
	Input.action_press(&"jump")
	await step(34)
	Input.action_release(&"jump")
	await step(12)
	check(player.velocity.y>0 and player.position.y<1000,"Late-jump probe is really falling")
	Input.action_press(&"jump")
	await step(3)
	check(player.double_jump_used and player.velocity.y<0,"Late second jump responds after the old animation window")
	# A falling player who has spent the second jump buffers the next ground jump.
	await reset()
	player.position.y=988
	player.air_state=LanPlayer.AirState.FALLING
	player.double_jump_used=true
	player.velocity.y=180
	player.play_air_animation(&"fall")
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	await step(8)
	check(player.air_state==LanPlayer.AirState.RISING and player.velocity.y<0,"Buffered jump fires on landing even with a direction held")
	check(not player.double_jump_used,"Landing replenishes second jump before takeoff")
	await reset()
	player.position.y=985
	player.air_state=LanPlayer.AirState.FALLING
	player.double_jump_used=true
	player.velocity.y=100
	player.play_air_animation(&"fall")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	var buffered_peak:=1000.0
	# Include the remaining fall and the full ascent before sampling the apex.
	for i in 60:
		await step(1)
		buffered_peak=minf(buffered_peak,player.position.y)
	print("BUFFERED JUMP HEIGHT=",1000.0-buffered_peak)
	check(absf((1000.0-buffered_peak)-full_height)<0.1,"A buffered tap released before landing reaches full jump height")
	await reset()
	player.position.y=988
	player.air_state=LanPlayer.AirState.FALLING
	player.velocity.y=180
	player.play_air_animation(&"fall")
	Input.action_press(&"ui_right")
	await step(8)
	check(player.air_state==LanPlayer.AirState.GROUNDED,"Directional landing never forces a roll")
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(8)
	check(player.velocity.x<0,"Landing immediately permits reversing")
	# Leave an authored finite floor, then press jump during edge grace.
	await reset()
	player.register_ground_surface(Rect2(-100,700,200,12))
	player.reset_after_map_fall(Vector2(98,700))
	Input.action_press(&"ui_right")
	for i in 30:
		await step(1)
		if player.air_state==LanPlayer.AirState.FALLING: break
	await step(2)
	Input.action_press(&"jump")
	await step(2)
	check(player.velocity.y<0 and not player.double_jump_used,"Edge grace uses the first jump, preserving second jump")
	await reset()
	Input.action_press(&"ui_right")
	await step(6)
	check(player.velocity.x>=179,"Walking reaches commanded speed within 100 ms")
	Input.action_release(&"ui_right")
	await step(4)
	check(absf(player.velocity.x)<0.1,"Release stops walking within 67 ms")
	for action in [&"start_attack_1x",&"start_attack_2x",&"start_attack_2x_1",&"start_attack_2x_2"]:
		await reset()
		player.call(action,1.0)
		await step(2)
		check(not player.can_cancel_normal_attack_recovery(),"%s retains its startup commitment" % action)
		var opened:=false
		for i in 100:
			await step(1)
			if player.can_cancel_normal_attack_recovery():
				opened=true
				break
			if player.attack_state==LanPlayer.AttackState.NONE: break
		if action==&"start_attack_2x_1":
			check(not opened and player.attack_state==LanPlayer.AttackState.NONE,"Short alternate ends with its effect and needs no artificial recovery window")
		else:
			check(opened,"%s opens recovery only after the authored effect closes" % action)
		Input.action_press(&"jump")
		await step(2)
		check(player.velocity.y<0 and player.attack_state==LanPlayer.AttackState.NONE and not player.combat_timeline.is_playing(),"%s jump cancels recovery and releases the old timeline" % action)
	release()
	expect_save_untouched()
	world.queue_free()
	await wait_frames(3)
	finish("LAN CONTROL FEEL")

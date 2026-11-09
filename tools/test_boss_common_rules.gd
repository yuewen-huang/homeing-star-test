extends SceneTree
## Component contract on every production boss, followed by real Lan input at Thomas.
var failures := 0
var room: BossDevelopmentRoom
var out := "D:/HomingStar/homeing-star-test/artifacts/boss-common-rules"
var reports: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1280,720)
	room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	for index in [0,1,3,4,5,6,7,8,10,11,12,13]:
		room.select_boss(index)
		var boss: DamageReceiver2D=room.adapter.boss
		var spacing: Node=boss.get_node("BodySpacing")
		room.player.input_frozen=false
		room.player.set_physics_process(true)
		check(not spacing.eligible(room.player),"Manual preview must not push: "+str(index))
		if boss is SandstormFighter:
			boss.combat_enabled=true
			boss.play_source("待机",true)
			boss._update_hurtbox()
		else: boss.set("manual_control",false)
		if boss is RegionalCoreBoss:
			boss.begin_encounter()
			boss.set_core_invulnerable(false)
		if boss is DeerDuelBoss:
			boss.opening=1
			boss.invulnerable=false
		if boss is MasterBoss:
			boss.combat_target=room.player
			boss.state=MasterBoss.State.RECOVER
		boss.set_physics_process(false) # Freeze AI only; player and spacing physics remain live.
		boss.set_process(false)
		var center: float=spacing.center_x()
		room.player.global_position=Vector2(center-2,room.FLOOR_Y)
		room.player.velocity=Vector2.ZERO
		await physics_frame
		check(spacing.eligible(room.player),"Grounded combat body missing: "+str(index))
		var first_x: float=room.player.global_position.x
		for tick in 70: await physics_frame
		var gap: float=center-room.player.global_position.x
		check(gap>=spacing.gap_for(room.player)-.1,"Overlap remains: "+str(index)+" gap="+str(gap))
		check(absf(first_x-(center-2))<=6.1,"Separation snapped instead of settling")
		var ordinary: Vector2=spacing.limit_motion(room.player,Vector2(100,0))
		check(ordinary.x<1,"Ordinary walk crossed body")
		room.player.ground_action_state=LanPlayer.GroundActionState.SLIDE
		check(spacing.limit_motion(room.player,Vector2(100,0)).x==100,"Slide blocked")
		room.player.ground_action_state=LanPlayer.GroundActionState.NONE
		room.player.air_state=LanPlayer.AirState.FALLING
		check(not spacing.eligible(room.player),"Aerial path blocked")
		room.player.air_state=LanPlayer.AirState.GROUNDED
		var feedback:=root.get_node("CombatFeedback") as CombatFeedbackService
		boss.reset_boss_counter()
		var child:=DamageReceiver2D.new()
		boss.add_child(child)
		for n in 6:
			var source: DamageReceiver2D=boss if n%2==0 else child
			var attack:=CombatAttackData.new(StringName("contract_%d"%n),source,1,0,0,0,CombatAttackData.DangerType.NORMAL)
			feedback.parry_landed.emit(source,attack,Vector2.ZERO,false)
			feedback.parry_landed.emit(source,attack,Vector2.ZERO,false)
			check(boss.defense_credit==n+1,"Count/duplicate/child ownership failed: "+str(index))
			if n==4: check(not boss.can_offer_break_empower(),"Five parries unlocked throw")
		check(boss.can_offer_break_empower(),"Six parries did not unlock recovery throw: "+str(index))
		boss.combat_stats.apply_health_damage(1)
		check(boss.defense_credit==6,"Being hit erased progress")
		boss.consume_break_empower()
		check(boss.defense_credit==0 and not boss.can_offer_break_empower(),"Throw did not consume credit")
		boss.set_counter_progress(4)
		boss.reset_boss_counter()
		check(boss.defense_credit==0,"Reset did not clear credit")
		reports.append({"boss":index,"body_gap":gap,"six_parry_contract":true})
		print("BOSS CONTRACT ",index," gap=",gap," failures=",failures)
	# These fixtures set spawn positions once, then use only ordinary real input.
	for mode in ["hug_left","hug_right","hug_hold","walk_out"]:
		room.select_boss(13)
		room.select_combo(1)
		room.set_combat_simulation(true)
		var boss: SandstormFighter=room.adapter.boss
		boss.set_process(false) # Stop automatic replay, retain actual skill/player/spacing clocks.
		var skill: SandstormThomas=boss.thomas
		var side := 1.0 if mode=="hug_right" else -1.0
		room.player.global_position=skill.global_position+Vector2(side*2,0)
		room.player.velocity=Vector2.ZERO
		var health: int=room.player.combat_stats.health
		var minimum:=health
		var max_step:=0.0
		var last_x: float=room.player.global_position.x
		var captured:=false
		var held:=false
		for tick in 500:
			if not is_instance_valid(skill): break
			if mode=="hug_hold" and not held:
				Input.action_press("ui_right")
				held=true
			if mode=="walk_out" and skill.elapsed>.5:
				var goal:=285.0+maxf(0,skill.elapsed-1.848)*70.0
				if absf(room.player.global_position.x-skill.global_position.x)<goal: Input.action_press("ui_left")
				else: Input.action_release("ui_left")
			await physics_frame
			minimum=mini(minimum,room.player.combat_stats.health)
			max_step=maxf(max_step,absf(room.player.global_position.x-last_x))
			last_x=room.player.global_position.x
			if is_instance_valid(skill) and skill.elapsed>2.1 and not captured:
				captured=true
				await capture(mode)
		Input.action_release("ui_left")
		Input.action_release("ui_right")
		check(minimum==health if mode=="walk_out" else minimum<health,mode+": wrong real damage outcome")
		check(max_step<12,mode+": visible teleport")
		reports.append({"case":mode,"minimum_health":minimum,"maximum_step":max_step})
		print("THOMAS BODY ",mode," hp=",minimum," max_step=",max_step)
	print("BOSS COMMON RULES: ",failures," failures")
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"reports":reports},"\t"))
	room.free()
	quit(0 if failures==0 else 1)

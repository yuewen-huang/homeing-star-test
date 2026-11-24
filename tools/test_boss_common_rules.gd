extends SceneTree
## Component contract on every production boss, followed by real Lan input at Thomas.
var failures := 0
var room: BossDevelopmentRoom
var out := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
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
		var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
		assist.begin_boss_attempt(room, room.player, boss, false)
		var duel := room.player.pulse_duel
		var child := DamageReceiver2D.new()
		boss.add_child(child)
		var hit := CombatAttackData.new(&"contract_normal", child, 10, 0, 0, 0)
		room.player.parry_resolved.emit(hit, false)
		room.player.parry_resolved.emit(hit, false)
		check(duel.player_energy == 14 and duel.boss_internal_hp == 15, "Child contact deposits once: " + str(index))
		for n in 4:
			var finisher := CombatAttackData.new(&"contract_finish", boss, 10, 0, 0, 0)
			finisher.combo_finisher = true
			room.player.parry_resolved.emit(finisher, false)
		check(duel.player_energy == 100 and duel.boss_internal_hp == 100, "Shared caps: " + str(index))
		check(not boss.boss_counter_enabled() and room.player.heal.charges == 2, "Only the encounter resource is active")
		var blade := AttackHitContext.new(&"attack_2x", 27, 0)
		var before_blade := duel.boss_stats.health
		var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
		feedback.settle_attack_hit(boss, blade, room.player.global_position)
		check(duel.boss_stats.health == before_blade - 10 and blade.health_damage == 27,
			"Sword hit settles for ten without mutating the move: " + str(index))
		var hp := duel.boss_stats.health
		check(duel.can_burst(), "Near exposed body accepts E: " + str(index))
		duel.detonate()
		for tick in 112: await physics_frame
		check(duel.pushes == 1 and duel.boss_stats.health == hp - 140 and not duel.performing, "One settled pulse on actor: " + str(index))
		assist.end_boss_attempt(room)
		check(room.player.pulse_duel == null and boss.pulse_duel == null, "Exit unbinds both actors")
		reports.append({"boss":index,"body_gap":gap,"pulse_damage":hp - int(boss.combat_stats.health)})
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
			if mode=="walk_out" and not skill.waves.is_empty():
				# Walk in the gap between the first two rings. Each ring expands from its spawn point.
				var first: Dictionary = skill.emission_log[0]
				var travel := clampf(skill.elapsed - float(first.time) - float(skill.config.warning_time), 0.0, float(skill.config.active_time))
				var gap := (float(skill.config.ring_radii[0]) + float(skill.config.ring_radii[1])) * 0.5
				var target_x := float(first.origin.x) - gap - travel * float(skill.config.ring_speed)
				if skill.elapsed >= float(first.time) + float(skill.config.warning_time) + float(skill.config.active_time):
					target_x = room.player.world_min_x
				if room.player.global_position.x > target_x: Input.action_press("ui_left")
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

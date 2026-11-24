extends SceneTree
## Real hard-mode parry presses across two casts, then the actual E input path.
var failures:=0
var room: BossDevelopmentRoom
var pressed: Dictionary={}
var out := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	root.size=Vector2i(1280,720)
	room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	room.select_combo(2)
	check(room.player.heal.charges==0,"Manual preview granted a heal")
	room.set_combat_simulation(true)
	check(room.player.heal.charges==2,"Practice opening did not grant two heals")
	root.get_node("BattleAssist").set_difficulty(1)
	var actor: SandstormFighter=room.adapter.boss
	var thrown:=false
	var throw_age:=0.0
	var duel := room.player.pulse_duel
	var max_energy := 0
	var expected_damage := 0
	var hp:=actor.combat_stats.health
	var minimum:=room.player.combat_stats.health
	var before_throw:=Vector2.ZERO
	var charged_captured := false
	var effect_checked := false
	for tick in 4800:
		var skill: SandstormAmbush=actor.ambush
		if is_instance_valid(skill) and not thrown:
			var key:=str(skill.get_instance_id())+":"+str(skill.count)
			if skill.phase==skill.Phase.ATTACK and skill.clock>=skill.CONTACT-.09 and not pressed.has(key):
				pressed[key]=true
				Input.action_press("parry")
			elif skill.phase==skill.Phase.FINISH_DROP and skill.clock>=skill.FINISH_FALL-.09 and not pressed.has(key+":finish"):
				pressed[key+":finish"]=true
				Input.action_press("parry")
			else: Input.action_release("parry")
		else: Input.action_release("parry")
		if duel.player_energy == 100 and not charged_captured and DisplayServer.get_name()!="headless":
			charged_captured=true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("pulse_ready.png"))
		if duel.player_energy == 100 and actor.looping_idle and not thrown:
			var side:=signf(actor.get_throw_anchor().x-room.player.global_position.x)
			Input.action_press("ui_right" if side>0 else "ui_left")
			if room.player.get_ready_throw_target()==actor:
				before_throw = CombatHitQuery.shape_rect(duel.hurt_shape).get_center()
				expected_damage = duel.BASE_PULSE_DAMAGE + floori(duel.boss_internal_hp)
				Input.action_release("ui_left")
				Input.action_release("ui_right")
				Input.action_press("interact")
				thrown=true
		else: Input.action_release("interact")
		await physics_frame
		minimum=mini(minimum,room.player.combat_stats.health)
		max_energy = maxi(max_energy, duel.player_energy)
		if thrown:
			throw_age+=1.0/60.0
			var fx := duel.burst_effect
			if not effect_checked and is_instance_valid(fx):
				check(fx.to_global(fx._boss_center).distance_to(before_throw)<15, "Burst visual missed the body")
				effect_checked = true
			if throw_age > 1.5:
				check(duel.player_energy == 0, "Actual E did not spend the full energy bar")
				check(actor.combat_stats.health == hp - expected_damage and effect_checked, "Burst must hit for base damage plus the stored wound")
				if DisplayServer.get_name()!="headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(out.path_join("real_input_burst.png"))
				break
	for action in ["parry","interact","ui_left","ui_right"]: Input.action_release(action)
	check(thrown and max_energy == 100, "Could not earn and execute the burst through actual input")
	check(minimum==100,"Parry fixture took damage")
	check(room.player.heal.charges == 2, "Parrying must preserve the opening flask count")
	room.player.combat_stats.apply_health_damage(25)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.physical_keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	await physics_frame
	await physics_frame
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	await physics_frame
	check(room.adapter.boss==actor and room.player.heal.charges==1,"R should spend a flask during combat without restarting")
	key = key.duplicate() as InputEventKey
	key.shift_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for i in 3: await physics_frame
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	check(not is_instance_valid(actor) and room.player.heal.charges==2,"Shift+R should restart with two fresh charges")
	check(room.player.pulse_duel.player_energy == 0, "Development retry retained energy")
	print("PULSE REAL INPUT: ",failures," failures; presses=",pressed.size()," max_energy=",max_energy," hp=",minimum," thrown=",thrown)
	FileAccess.open(out.path_join("counter_input.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"presses":pressed.size(),"max_energy":max_energy,"minimum_health":minimum,"thrown":thrown},"\t"))
	room.free()
	quit(0 if failures==0 else 1)

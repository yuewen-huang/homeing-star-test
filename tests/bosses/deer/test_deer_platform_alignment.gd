extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss
var lan: LanPlayer
func run() -> void:
	use_memory_progress()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	for phase in [1,2]:
		for i in BossDevelopmentRoom.BOSS_CATALOG.size():
			var suffix := "/deer_duel_adapter.gd" if phase==1 else "/deer_root_duel_adapter.gd"
			if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with(suffix): room.select_boss(i)
		await process_frame
		deer=room.adapter.boss
		lan=room.player
		room.dummy.hide()
		deer.set_physics_process(false)
		lan.set_physics_process(false)
		if phase==2: (deer as DeerRootDuelBoss).terrain.advance(2.5)
		var y := deer.ground_y_at(640)
		for facing in [-1,1]:
			for move_index in 4:
				deer.cancel_duel(false)
				deer.position=Vector2(820 if facing<0 else 460,y)
				lan.reset_after_map_fall(Vector2(deer.position.x+facing*220,y))
				lan.set_physics_process(false)
				deer.start_move(move_index,lan.position.x)
				if move_index==2: lan.position.x=1000 # Inspect the blade unobscured by Lan.
				var saw := false
				var aligned := true
				var landed := false
				for f in 180:
					deer._physics_process(1.0/60)
					var probes := deer.attack_probes()
					for probe in probes:
						saw=true
						var at: Vector2 = probe.transform.origin
						aligned = aligned and at.y < y+5 and at.y>y-200
					if move_index==1 and is_instance_valid(deer.effects._landing):
						landed = is_equal_approx(deer.effects._landing.global_position.y,deer.ground_y_at(deer._aim))
					if facing==1 and move_index==2 and f in [37,43,48]: await capture("sweep_p%d_%d" % [phase,f])
					if facing==1 and move_index==1 and f==63: await capture("landing_p%d" % phase)
				check(saw and aligned,"Phase %d move %d facing %d keeps contact at its actual floor" % [phase,move_index,facing])
				if move_index==1: check(landed,"Landing earth effect shares the actual contact floor")
				if move_index==2: check(deer.effects._main.is_empty(),"Sweep tail cleans up after complete follow-through")
		# Exact shared ribbon/contact end points, in both directions.
		for facing in [-1,1]:
			deer.cancel_duel(false)
			deer.position=Vector2(640,y)
			deer.start_move(2,640+facing*220)
			deer.age=.71
			deer._duel_sweep()
			deer.effects.sync(deer)
			var ribbon: Node2D=deer.effects._main[0]
			var pose: Dictionary=ribbon.blade_pose(.13)
			var expected: Vector2=pose.tip*Vector2(facing,1)
			check(expected.distance_to(deer.geometry.points[-1])<.01,"New horn crescent leading tip matches live hit geometry")
		deer.cancel_duel(false)
	deer.effects.advance(.6)
	# The current specimen is phase two.
	var root_deer := deer as DeerRootDuelBoss
	var wave: Node2D=root_deer.contest_wave
	var variants := {}
	for pulse in 3:
		for spike in wave.spike_layout(pulse): variants[spike.key]=true
	var complete_art := true
	var edges: Vector2=wave.summit_edges()
	for spike in wave.spike_layout(0):
		for frame: Dictionary in DeerRootArt.clip(spike.key).frames:
			var left: float=spike.x+frame.offset[0]*1.4
			var right: float=left+frame.region[2]*1.4
			complete_art = complete_art and (right<=edges.x if spike.x<edges.x else left>=edges.y)
	check(complete_art,"Complete painted root frames fit beside the summit without image clipping")
	check(variants.size()==9,"Root waves reuse all nine short/medium/high painted shapes")
	for x in [25.0,75.0,115.0,1165.0,1205.0,1255.0]:
		check(wave.exposed(Vector2(x,deer.ground_y_at(x))),"Slope camping at %.0f is covered by visible tall roots" % x)
	check(not wave.exposed(Vector2(640,415)),"Flat summit remains the actual safe area")
	wave.reset()
	wave.clock=3.65
	wave.advance(.001)
	await capture("mixed_root_wave")
	lan.set("combat_simulation",true)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	# Verify an actual hurtbox receives a root contact at the screenshot's slope.
	lan.reset_after_map_fall(Vector2(100,deer.ground_y_at(100)))
	lan.combat_stats.restore_health()
	lan.set_physics_process(false)
	var hp := lan.combat_stats.health
	wave.reset()
	for f in 270: wave.advance(1.0/60)
	check(lan.combat_stats.health<hp,"Actual root contacts hit the formerly safe slope position")
	# Real hit settlement, not only debug shape heights, for all four attacks.
	root_deer.root_exercise=0 # Isolate body contacts from the independent arena wave.
	for facing in [-1,1]:
		for index in 4:
			deer.cancel_duel(false)
			deer.manual_control=false
			deer.position=Vector2(820 if facing<0 else 460,415)
			lan.reset_after_map_fall(Vector2(deer.position.x+facing*220,415))
			lan.combat_stats.restore_health()
			lan.set_physics_process(false)
			var before := lan.combat_stats.health
			deer.start_move(index,lan.position.x)
			for f in 200:
				deer._physics_process(1.0/60)
				if deer.move==&"": deer.wait_left=999
			check(lan.combat_stats.health<before,"Real platform move %d hits correctly facing %d" % [index,facing])
	deer.manual_control=true
	root_deer.root_exercise=-1
	root_deer.cancel_duel(false)
	root_deer.position=Vector2(640,415)
	lan.position=Vector2(450,415)
	root_deer._yield_platform()
	root_deer._update_opening(.4)
	check(absf(root_deer.position.x-640)<=48.1,"One parry cannot send the deer across the entire platform")
	root_deer.start_move(2,450)
	root_deer._begin_contact(0)
	check(root_deer.attack_hitbox.attack.launch_velocity==0 and root_deer.attack_hitbox.attack.knockback_speed==DeerRootDuelBoss.IMPACT_SPEEDS[&"sweep"],"Phase-two sweep uses its authored ground push without launching the player")
	# Repeated manual drops must never remove or summon the stage platform.
	root_deer.cancel_duel(false)
	root_deer._start_exercise(1)
	check(root_deer.move==&"drop" and not root_deer.terrain.retiring and root_deer.terrain.roots.size()==1,"Drop practice preserves the sole stage platform")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER TERRAIN ALIGNMENT")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

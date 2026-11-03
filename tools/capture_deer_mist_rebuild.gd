extends "../tests/support/harness.gd"
const Quake = preload("res://scripts/bosses/master/studio_vfx/quake_effect.gd")
func run() -> void:
	use_memory_progress()
	var started := Time.get_ticks_msec()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	print("ROOM_READY_MS=", Time.get_ticks_msec()-started)
	room.set_combat_simulation(true)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	deer.mist.set_process(false)
	deer.manual_control = true
	deer._rng.seed = 55
	var output := "D:/HomingStar/homeing-star-test/artifacts/deer-mist-rebuild"
	DirAccess.make_dir_recursive_absolute(output)
	var costs: Array[float] = []
	var frame_costs: Array[float] = []
	var captured := {}
	var max_effects := 0
	var nodes := []
	var buckets := {}
	Quake.Layer.profile = true
	for frame in (1200 if "--profile" in OS.get_cmdline_user_args() else 3600):
		if frame % 600 == 0:
			deer.reset_phase(true,false)
			deer.position = Vector2(850,555)
			room.player.reset_after_map_fall(Vector2(440,555))
			room.player.set_physics_process(false)
			match (frame / 600) as int % 3:
				0: deer.start_combo(&"mist_steps_red")
				1: deer.start_attack(DeerBoss.State.CHARGE)
				2: deer.start_mist_hunt()
		room.player.position.y = 300
		var before := Time.get_ticks_usec()
		deer._physics_process(1.0/60)
		deer.vfx._process(1.0/60)
		deer.mist._process(1.0/60)
		if frame > 60: costs.append((Time.get_ticks_usec()-before)/1000.0)
		max_effects = maxi(max_effects,deer.vfx._painted.size()+deer.vfx._stomp_quakes.size())
		await process_frame
		await RenderingServer.frame_post_draw
		if frame > 60: frame_costs.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		var bucket := "quake" if not deer.vfx._stomp_quakes.is_empty() else "other"
		if not buckets.has(bucket): buckets[bucket] = []
		buckets[bucket].append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		var shot := ""
		if deer.state == DeerBoss.State.HEAVY and absf(deer.red_warning_age()-DangerFlash.PEAK_TIME)<.02: shot = "stomp_red"
		if deer.state == DeerBoss.State.HUNT_WARNING and absf(deer._time-deer.mist_warning_duration()+.1)<.02: shot = "hunt_%d" % deer._hunt_round
		if deer.state == DeerBoss.State.HUNT_CHARGE and deer._time > .3: shot = "rush_%d" % deer._hunt_round
		if not shot.is_empty() and not captured.has(shot):
			captured[shot] = true
			root.get_texture().get_image().save_png(output.path_join(shot+".png"))
		if frame % 600 == 599: nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	deer._end_hunt()
	deer._recover(0)
	deer.vfx.clear_attacks()
	for i in 180:
		deer.vfx._process(1.0/60)
		await process_frame
	costs.sort()
	frame_costs.sort()
	var report := "CPU boss+VFX ms p50=%.3f p95=%.3f max=%.3f; engine process ms p50=%.3f p95=%.3f; live effect peak=%d; nodes=%s" % [costs[costs.size()/2],costs[int(costs.size()*.95)],costs[-1],frame_costs[frame_costs.size()/2],frame_costs[int(frame_costs.size()*.95)],max_effects,str(nodes)]
	print(report)
	for bucket in buckets:
		buckets[bucket].sort()
		print("BUCKET ",bucket," p50=",buckets[bucket][buckets[bucket].size()/2]," p95=",buckets[bucket][int(buckets[bucket].size()*.95)])
	print("LAYER_DRAW_US=",Quake.Layer.spent)
	FileAccess.open(output.path_join("performance.txt"),FileAccess.WRITE).store_string(report)
	check(max_effects <= 6, "Repeated attacks keep simultaneous effect instances bounded")
	check(deer.vfx._painted.is_empty() and deer.vfx._stomp_quakes.is_empty(), "Ending the run releases all transient attack effects")
	if not "--profile" in OS.get_cmdline_user_args(): check(captured.has("hunt_2") and captured.has("hunt_3"), "Native render captured red and gold hunt warnings through fog")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("DEER MIST NATIVE PERFORMANCE")

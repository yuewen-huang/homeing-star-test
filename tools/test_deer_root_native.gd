extends "../tests/support/harness.gd"
var contacts: Array[int] = []
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=pressed
	Input.parse_input_event(event)
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room); current_scene=room
	await process_frame
	await process_frame
	room.select_combo(1)
	room.combo_picker.select(1)
	room.set_playback_speed(2)
	room.set_combat_simulation(true)
	var deer: DeerBoss=room.adapter.deer
	var lan: LanPlayer=room.player
	deer.manual_control=true
	deer.root_phase.item_available=false
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	assist.set_player_invincible(false)
	deer.attack_hitbox.hit_resolved.connect(func(_target,result): contacts.append(result))
	deer.position=Vector2(800,555)
	lan.reset_after_map_fall(Vector2(650,555))
	Input.action_press(&"ui_right")
	await physics_frame
	Input.action_release(&"ui_right")
	deer.root_phase.pattern.start(false)
	# Inspect the real terminal strike in isolation; movement route is exercised below.
	deer.root_phase.round_index=2
	deer.root_phase.pattern.approaching=true
	deer.root_phase.elapsed=deer.root_phase.pattern.finish_at
	var pressed := false
	var health := lan.combat_stats.health
	for i in 240:
		if deer.root_phase.pattern.finishing and not pressed and deer.root_phase.elapsed >= deer.root_phase.pattern.finish_at+deer.root_phase.pattern.release-.08:
			key(KEY_K,true); pressed=true
		else: key(KEY_K,false)
		await physics_frame
		if not deer.root_phase.active: break
	key(KEY_K,false)
	check(contacts.has(CombatHitResult.Type.PARRY_SUCCESS) and not deer.root_phase.active,"Actual K red counter interrupts root horn")
	check(lan.combat_stats.health==health,"Red counter works without invincibility or relic")
	# Native visual/performance loop runs production action time, with observer out of hit range.
	room.set_physics_process(false)
	deer.set_physics_process(false); deer.vfx.set_process(false)
	lan.set_physics_process(false)
	var output := "D:/HomingStar/homeing-star-test/artifacts/deer-root-rebuild"
	DirAccess.make_dir_recursive_absolute(output)
	var costs: Array[float]=[]
	var engine: Array[float]=[]
	var shots := {}
	var nodes := []
	var peak := 0
	for frame in 4800:
		if frame%600==0:
			deer.reset_phase(true,false); deer.short_stun_remaining=0
			deer.position=Vector2(850,555)
			lan.reset_after_map_fall(Vector2(560,555)); lan.set_physics_process(false)
			match (frame/600) as int % 4:
				0: deer.start_combo(&"root_steps")
				1: deer.root_phase.add_nodule(Vector2(650,555)); deer.start_attack(DeerBoss.State.HEAVY)
				2: deer.root_phase.pattern.start(false)
				3: deer.root_phase.pattern.start(true)
		lan.position.y=250
		var before := Time.get_ticks_usec()
		deer._physics_process(1.0/60)
		deer.vfx._process(1.0/60)
		costs.append((Time.get_ticks_usec()-before)/1000.0)
		peak=maxi(peak,deer.root_phase.volleys.size())
		await process_frame
		await RenderingServer.frame_post_draw
		engine.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		var label := ""
		if deer.state==DeerBoss.State.ROOT_HUNT and absf(deer.red_warning_age()-DangerFlash.PEAK_TIME)<.02: label="red_horn"
		if deer.state==DeerBoss.State.HEAVY and deer._time>1.8 and deer._time<2: label="heavy_roots"
		if deer.root_phase.active and deer.root_phase.elapsed>4.1 and deer.root_phase.elapsed<4.2 and deer.root_phase.pattern.ultimate: label="tide"
		if frame==590: label="steps_recovery"
		if not label.is_empty() and not shots.has(label):
			shots[label]=true
			root.get_texture().get_image().save_png(output.path_join(label+".png"))
		if frame%600==599: nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	costs.sort(); engine.sort()
	var report := "Boss+VFX CPU ms p50=%.3f p95=%.3f max=%.3f; engine process p50=%.3f p95=%.3f; active volleys peak=%d; nodes=%s" % [costs[costs.size()/2],costs[int(costs.size()*.95)],costs[-1],engine[engine.size()/2],engine[int(engine.size()*.95)],peak,str(nodes)]
	print(report)
	FileAccess.open(output.path_join("performance.txt"),FileAccess.WRITE).store_string(report)
	check(peak<=3,"Native effects stay bounded through all four arrangements")
	check(nodes[-1]<=nodes[3]+3,"Second full cycle does not accumulate scene nodes")
	check(shots.has("red_horn") and shots.has("tide"),"Native render reaches red finisher and directional tide")
	room.free(); current_scene=null
	expect_save_untouched()
	finish("DEER ROOT NATIVE")

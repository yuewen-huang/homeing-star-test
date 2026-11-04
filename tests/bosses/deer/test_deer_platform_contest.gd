extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerRootDuelBoss
var lan: LanPlayer
func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_root_duel_adapter.gd"): room.select_boss(i)
	room.set_combat_simulation(true)
	deer = room.adapter.boss
	lan = room.player
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	room.set_physics_process(false)
	deer._ensure_contest_platform()
	deer.terrain.advance(1.2)
	check(deer.terrain.roots.size()==1 and deer.terrain.roots[0].progress>.6 and deer.terrain.roots[0].progress<.7,"One stage platform rises slowly rather than erupting")
	check(not deer.contest_wave.running,"Root pressure stays off during stage entry")
	deer.terrain.advance(1.2)
	check(deer.terrain.roots[0].top>=1000,"Summit fits a full rush plus both bodies")
	check(is_equal_approx(deer.ground_y_at(640),415),"Summit stands above the root wave")
	check(is_equal_approx(lan.sloped_ground_surfaces.size(),3),"One persistent contest layout owns three supports")
	var wave := deer.contest_wave
	check(not wave.exposed(Vector2(640,415)),"Summit is safe")
	check(wave.exposed(Vector2(-200,555)),"Lowland is exposed")
	check(not wave.exposed(Vector2(-200,180)),"A body above the actual tall root footprint is safe")
	lan.position = Vector2(-200,555)
	deer.position = Vector2(640,415)
	var hp := lan.combat_stats.health
	wave.advance(2.8)
	check(lan.combat_stats.health==hp,"Full advance warning has no damage")
	wave.clock = 3.45
	wave.advance(.01)
	check(lan.combat_stats.health<hp,"Lowland root wave causes actual shared damage")
	hp = lan.combat_stats.health
	wave.advance(.01)
	check(lan.combat_stats.health==hp,"One pulse cannot repeatedly damage the same player")
	wave.reset()
	lan.position = Vector2(640,415)
	deer.position = Vector2(-200,555)
	hp = deer.combat_stats.health
	wave.clock = 3.45
	wave.advance(.01)
	check(deer.combat_stats.health<hp,"The deer also loses health when displaced into lowland")
	check(lan.combat_stats.health>0,"Summit player survives the wave")
	deer.cancel_duel(false)
	deer.position = Vector2(770,415)
	lan.position = Vector2(600,415)
	deer._yield_platform()
	deer._update_opening(.4)
	check(deer.position.x>770 and deer.position.x<=818.1,"A true break yields a little space instead of throwing deer off the summit")
	deer.cancel_duel(false)
	deer.position = Vector2(-200,555)
	lan.position = Vector2(1450,555)
	deer.wait_left=0
	deer._contest_selection(.2)
	check(deer.move==&"drop" and deer._aim>240 and deer._aim<1040,"Deer commits a return landing on the actual summit even if both are below")
	lan.position = Vector2(640,415)
	deer._contest_selection(.02)
	check(deer.move==&"drop","Deer contests an occupied summit with a locked landing")
	deer.cancel_duel(false)
	deer.position=Vector2(760,415)
	lan.position=Vector2(540,415)
	deer.wait_left=0
	deer._contest_selection(.02)
	for f in 60:
		if deer.move!=&"": break
		deer._contest_selection(1.0/60)
	check(deer.pressure.active and deer.move!=&"","Summit occupation begins a continuous phrase after bounded footwork")
	deer.cancel_duel(false)
	deer.start_move(2,540)
	deer.age=DeerDuelBoss.SWEEP_PREP+DeerDuelBoss.SWEEP_ACTIVE+.001
	deer._duel_sweep()
	var seen: Dictionary = {}
	var clean := true
	for f in 95:
		deer._update_opening(1.0/60)
		seen["%s:%d" % [deer.animated_sprite.animation,deer.animated_sprite.frame]]=true
		clean = clean and deer.attack_probes().is_empty()
	for frame in range(5,12): check(seen.has("flick_ING:%d" % frame),"Sweep keeps follow-through source frame %d" % frame)
	for frame in 10: check(seen.has("flick_END:%d" % frame),"Sweep keeps recovery frame %d" % frame)
	check(clean,"Restored follow-through creates no extra damage")
	# Real input traverses the raised support in both directions.
	deer.manual_control = true
	lan.set_physics_process(true)
	for side in [-1,1]:
		lan.reset_after_map_fall(Vector2(1520 if side<0 else -240,555))
		Input.action_press(&"ui_left" if side<0 else &"ui_right")
		var highest := 555.0
		for f in 720:
			await physics_frame
			highest = minf(highest,lan.position.y)
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		check(highest < 420,"Real walking reaches the summit from side %d" % side)
		check(lan.position.x<400 if side<0 else lan.position.x>900,"Real walking crosses both slopes without trapping")
	lan.set_physics_process(false)
	# Native stills: three states with real game art, no computer-use.
	deer.cancel_duel(false)
	deer.position=Vector2(790,415)
	lan.reset_after_map_fall(Vector2(520,415))
	lan.play_idle()
	wave.reset()
	wave.advance(2.5)
	await capture("contest_warning")
	wave.clock=3.5
	wave.advance(.01)
	await capture("contest_wave")
	wave.clock=6.5
	wave.advance(.01)
	await capture("contest_rest")
	# Sustained production AI, normal input only after the initial setup.
	deer.manual_control = false
	deer.restart_duel()
	lan.reset_after_map_fall(Vector2(450,555))
	lan.combat_stats.restore_health()
	lan.set_physics_process(true)
	deer.set_physics_process(true)
	var moves_seen := 0
	var last_move := &""
	var completed_wave_cycle := false
	for f in 1200:
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		if lan.position.x < 510: Input.action_press(&"ui_right")
		elif lan.position.x > 590: Input.action_press(&"ui_left")
		if f%28==0:
			var event := InputEventKey.new()
			event.physical_keycode=KEY_K
			event.keycode=KEY_K
			event.pressed=true
			Input.parse_input_event(event)
		if f%28==2:
			var event := InputEventKey.new()
			event.physical_keycode=KEY_K
			event.keycode=KEY_K
			event.pressed=false
			Input.parse_input_event(event)
		await physics_frame
		completed_wave_cycle = completed_wave_cycle or deer.contest_wave.cycle>=1
		if deer.move != last_move and deer.move != &"": moves_seen += 1
		last_move=deer.move
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	check(moves_seen >= 4,"Sustained real-input fight keeps selecting attacks")
	check(completed_wave_cycle,"Root pressure continues through attacks and recovery before any practice defeat reset")
	check(deer.terrain.roots.size()==1,"Contested platform persists through sustained combat")
	deer.set_physics_process(false)
	lan.set_physics_process(false)
	deer.restart_duel()
	check(deer.terrain.roots.size()==1 and deer.terrain.roots[0].progress==0 and not wave.running,"Retry restarts the single stage platform and clears wave contacts")
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("ROOT PLATFORM CONTEST")
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

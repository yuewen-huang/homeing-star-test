extends "../../support/harness.gd"

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func run() -> void:
	use_memory_progress()
	var room: Chapter1DeerBossRoom=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro:=WindSightingComic.new()
	var packed:=PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	room.encounter._spawn_phase(3,1420)
	room.encounter.start()
	var boss: Node2D=room.deer
	boss.manual_control=true
	boss.set_physics_process(false)
	room.player.reset_after_map_fall(Vector2(1250,555))
	room.player.set_physics_process(false)
	boss.arena.begin(1)
	boss.arena.burst(1420)
	boss.arena.advance(.4)
	await wait_frames(3)
	await capture("stomp_warning")
	boss.arena.advance(.28)
	await wait_frames(3)
	await capture("stomp_live")
	check(boss.arena.hazards.size()>0 and boss.arena.hazards[0].armed,"Ground thorns remain armed during painted hold")
	for next in [0,1,2,4,5,6]:
		boss.restart_duel()
		boss.set_physics_process(false)
		boss.manual_control=false
		boss.pressure.selected=-1
		boss.position=Vector2(1420,555)
		boss.start_phrase(2)
		var live_frames:=0
		var followed:=false
		for i in 110:
			boss._physics_process(1.0/60)
			if boss.move==&"pursuit_step" and boss.pressure.groups_used==2 and not followed:
				boss.pressure.group=next
				followed=true
			if boss.arena.hazards.any(func(h): return h.armed):
				live_frames+=1
				if live_frames==12 and next==0: await capture("stomp_production_hold")
			await physics_frame
		print("STOMP FOLLOW ",next," live frames ",live_frames," final ",boss.move)
		check(live_frames>=29,"Stomp holds real thorns through follow-up %d"%next)
	boss.restart_duel()
	boss.set_physics_process(false)
	boss.manual_control=true
	boss.preview_aim=Vector2(1250,555)
	boss.arena.begin(4)
	boss.start_scene_move(&"sky_cast")
	var captured: Dictionary={}
	var frame_ms: Array[float]=[]
	var slow_frames: Array=[]
	var safe_gap:=true
	var player_shape:=RectangleShape2D.new()
	player_shape.size=Vector2(28,58)
	for f in 360:
		var tick:=Time.get_ticks_usec()
		boss.arena.advance(1.0/60)
		boss.age=f/60.0
		boss._sky_cast()
		if f in [85,100,145,208,221,283,301]:
			await wait_frames(2)
			await capture("rain_%03d"%f)
		for h in boss.arena.hazards:
			if h.falling and h.armed:
				for probe in h.contact.probes():
					safe_gap=safe_gap and not probe.shape.collide(probe.transform,player_shape,Transform2D(0,Vector2(1370,526)))
			if h.armed and h.contact.path.size()>1 and not captured.has(h.serial):
				check(h.contact.path[0].distance_to(h.base)<.01,"Rain collision begins on the painted diagonal")
				captured[h.serial]=true
		if boss.move!=&"sky_cast": break
		await physics_frame
		if f>60 and not f in [85,100,145,208,221,283,301]:
			var ms:=(Time.get_ticks_usec()-tick)/1000.0
			frame_ms.append(ms)
			if ms>45: slow_frames.append([f,snappedf(ms,.1),boss.arena.hazards.size()])
	check(captured.size()==5,"Four ultimate phrases deliver five separately timed impacts")
	check(safe_gap,"The warned midpoint remains safe at real player height through both crossing ranks")
	frame_ms.sort()
	print("RAIN_NATIVE_FRAME_MS median=",frame_ms[frame_ms.size()/2]," p95=",frame_ms[int(frame_ms.size()*.95)]," max=",frame_ms.back())
	print("RAIN_SLOW_FRAMES ",slow_frames)
	boss.restart_duel()
	boss.set_physics_process(false)
	boss.position=Vector2(1000,555)
	boss.preview_aim=Vector2(1580,555)
	boss.plow.start()
	for f in 100:
		boss.age=f/60.0
		boss.plow.execute()
		boss.effects.advance(1.0/60)
		boss.effects.sync(boss)
		if f in [47,62,78]:
			await wait_frames(2)
			await capture("plow_dust_%03d"%f)
	expect_save_untouched()
	finish("VINE RENDER")

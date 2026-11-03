extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room); current_scene=room
	await process_frame
	await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	var deer: DeerBoss=room.adapter.deer
	deer.set_physics_process(false); deer.vfx.set_process(false)
	deer.phase=2
	deer.reset_phase(true,false)
	var roots := deer.root_phase
	var nodule := roots.add_nodule(Vector2(550,555))
	var before := deer.combat_stats.poise
	nodule.receive_hit()
	check(deer.combat_stats.poise==before,"Damaging an intact nodule does not grant early poise reward")
	nodule.receive_hit()
	check(deer.combat_stats.poise==before-12,"Destroying nodule removes twelve boss poise")
	nodule.break_nodule()
	check(deer.combat_stats.poise==before-12,"Destroyed nodule cannot pay twice")
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise-8)
	roots.add_nodule(Vector2(700,555)).break_nodule()
	check(deer.poise_broken and deer.state==DeerBoss.State.RECOVER and deer.can_offer_break_empower(),"Nodule reward uses normal poise-break transition")
	deer.reset_phase(true,false)
	before=deer.combat_stats.poise
	for x in [300,500,700,900]: roots.add_nodule(Vector2(x,555))
	roots.reset_all()
	check(deer.combat_stats.poise==before,"Replacement and reset never grant nodule rewards")
	var output := "D:/HomingStar/homeing-star-test/artifacts/deer-stomp-family"
	DirAccess.make_dir_recursive_absolute(output)
	for phase in range(1,5):
		deer.phase=phase
		deer.reset_phase(true,false)
		deer.position=Vector2(820,555)
		deer.direction=-1
		deer.vfx.prepare_stomps()
		await process_frame
		for heavy in [false,true]:
			deer.vfx.clear_attacks()
			var clip := &"heavy_ING" if heavy else &"light_ING"
			var frame := 0 if heavy else 1
			deer._show_clip(clip,frame)
			var at := deer.position+Vector2(deer._anchor_offset(clip,frame,"hoof").x,0)
			if heavy: deer.vfx.burst(at)
			else: deer.vfx.light_hoof_impact(at)
			check(deer.vfx._painted.is_empty() and deer.vfx._stomp_quakes.size()==1,"Phase %d hoof uses Studio instead of painted sequence"%phase)
			var effect: Node2D=deer.vfx._stomp_quakes[0]
			check(effect.spec.unit=="sword" and effect.spec.form=="crescent" and effect.spec.trail=="flame" and effect.spec.mode=="radial" and not effect.spec.reverse,"All phases preserve the user's exact crescent/flame/radial selection")
			check(effect.z_index+2<SideviewLayers.PLAYER,"Dust and glow stay below Lan")
			deer.vfx._process(.22 if heavy else .12)
			if DisplayServer.get_name()!="headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("phase_%d_%s.png"%[phase,"heavy" if heavy else "light"]))
			deer.vfx._process(4)
			check(deer.vfx._stomp_quakes.is_empty() and deer.vfx._stomp_pool.size()==3,"Phase pool returns to three dormant instances")
	deer.phase=2
	deer.reset_phase(true,false)
	deer.vfx.prepare_stomps()
	var ids := {}
	for effect in deer.vfx._stomp_pool: ids[effect.get_instance_id()]=true
	var costs: Array[float]=[]
	var peak := 0
	for i in 600:
		var before_us := Time.get_ticks_usec()
		if i%45==0: deer.vfx._stomp_quake(Vector2(650,555),i%90==0)
		deer.vfx._process(1.0/60)
		costs.append((Time.get_ticks_usec()-before_us)/1000.0)
		peak=maxi(peak,deer.vfx._stomp_quakes.size())
		if DisplayServer.get_name()!="headless":
			await process_frame
			await RenderingServer.frame_post_draw
	deer.vfx.clear_attacks()
	check(peak<=3 and deer.vfx._stomp_pool.all(func(effect): return ids.has(effect.get_instance_id())),"Continuous impacts reuse only the three warmed instances")
	costs.sort()
	var report := "VFX CPU ms p50=%.3f p95=%.3f max=%.3f; peak=%d"%[costs[300],costs[570],costs[-1],peak]
	print(report)
	FileAccess.open(output.path_join("performance.txt"),FileAccess.WRITE).store_string(report)
	room.free(); current_scene=null
	expect_save_untouched()
	finish("DEER STOMP FAMILY")

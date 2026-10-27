extends "../support/harness.gd"
## Also runnable with a real renderer: waits for drawing, without taking screenshots.
func run() -> void:
	use_memory_progress()
	var host := Node2D.new()
	root.add_child(host)
	var gold := DangerFlash.new(&"gold")
	var red := DangerFlash.new(&"red")
	host.add_child(gold)
	host.add_child(red)
	gold.show_at(.06,1,Vector2(320,240))
	red.show_at(.06,1,Vector2(640,240))
	check(is_equal_approx(gold.pieces[0].modulate.a,red.pieces[0].modulate.a),"Gold and red share the same brightness curve")
	check(gold.scale==Vector2.ONE and red.scale==Vector2.ONE,"Gold and red retain the original star dimensions")
	check(gold.z_index==DangerFlash.GOLD_Z and not gold.z_as_relative,"Gold renders above busy combat effects")
	check(gold.pieces.all(func(piece: PixelSlash) -> bool: return piece._display.material==null),"Gold uses the original baked art without the rejected outline")
	check(red.pieces.all(func(piece: PixelSlash) -> bool: return piece._display.material==null),"Red retains its existing baked appearance")
	gold.show_at(DangerFlash.PEAK_TIME,-1,Vector2(320,240))
	check(gold.modulate.a==1 and gold.scale.x<0,"Gold peak timing and mirroring remain intact")
	gold.kind=&"red"
	gold.show_at(.18,1,Vector2(320,240))
	check(gold.z_index==0 and gold.z_as_relative and gold.scale==Vector2.ONE,"Switching back to red restores its original layer and size")
	gold.kind=&"gold"
	gold.show_at(.18,1,Vector2(320,240))
	var crab := CrystalCrabQuakeVFX.new()
	host.add_child(crab)
	crab.cue(2,.18,Vector2(400,400))
	check(crab.glint.scale==Vector2.ONE*DangerFlash.GOLD_SCALE,"Crab uses the same global gold size")
	check(crab.glint_pieces.all(func(piece: PixelSlash) -> bool: return piece._display.material==null),"Crab gold warnings also restore the original unoutlined art")
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	var boss: MasterBoss = room.get_node("MasterBoss")
	boss.set_process(false)
	boss.manual_control=true
	room.get_node("Lan").set_physics_process(false)
	boss._enter_phase_2()
	boss.start_phase_2_body_action(&"master_phase2_pressure_five")
	boss._process(.72)
	var draws := 0
	for row: Dictionary in boss.phase_2_body_action.vfx.effects.values():
		if row.event.do!="slash": continue
		var claw: Node2D = row.effect.claw
		check(claw._mesh_node.mesh!=null and claw.look=="pixel","Current Studio claw produces a live production mesh")
		check(is_equal_approx(claw.trail,.1),"Current editor renderer preserves the authored 100 ms trail")
		var mesh: Array = claw._mesh_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = mesh[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = mesh[Mesh.ARRAY_TEX_UV]
		var widest_trail := 0.0
		for i in range(1,uvs.size()-1):
			if is_equal_approx(uvs[i].x,.62):
				widest_trail = maxf(widest_trail,vertices[i-1].distance_to(vertices[i+1])*float(claw.pixel))
		check(widest_trail>float(claw.width)*.4,"Real emitted trail retains its former sweep width instead of a thin hairline")
		for particle: Dictionary in claw.particles:
			check(float(particle.size)*float(claw.debris_size)<=1.4,"Debris uses fine specks instead of coarse blocks")
		draws += 1
	check(draws>0,"Real phase-two action emitted the new claw style")
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
	boss._interrupt_phase_2_action(0)
	expect_save_untouched()
	finish("DANGER FLASH READABILITY")

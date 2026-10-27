extends "../tests/support/harness.gd"
## Actual development-room action and imported renderers, sampled on the production clock.
func run() -> void:
	use_memory_progress()
	var move: StringName=&"mountain"
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var frames := false
	if output.is_empty(): output="E:/HomingStar/homeing-star-test/artifacts/master_phase1_qi"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--move="): move=StringName(arg.trim_prefix("--move="))
		elif arg.begins_with("--out="): output=arg.trim_prefix("--out=")
		elif arg=="--frames": frames=true
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene=room
	room.select_boss(1)
	room.set_process(false)
	room.player.input_frozen=true
	room.player.position=Vector2(180,555)
	for child in room.get_children():
		if child is CanvasLayer: child.hide()
	var master: MasterBoss=room.adapter.master
	master.set_process(false)
	master.position=Vector2(420,555)
	master.movement_direction=1
	room.adapter.target.position=Vector2(780,555)
	var camera := Camera2D.new()
	camera.position=Vector2(640,360)
	room.add_child(camera)
	camera.make_current()
	var title_layer := CanvasLayer.new()
	room.add_child(title_layer)
	var title := Label.new()
	title.text=master.action_library.label(move)
	title.position=Vector2(24,20)
	title.add_theme_font_size_override("font_size",26)
	title_layer.add_child(title)
	master.start_phase_1_action(move)
	var action := master.phase_1_action
	var cut: Dictionary=action.timeline.cuts[-1]
	print("ACTION ",move," release=",cut.release," contact=",cut.contact_at," duration=",action.timeline.duration," WARN=",action.timeline.warnings)
	var start := maxf(0,float(cut.release)-.65)
	while action.elapsed<start-.00001:
		master._process(minf(1.0/120,start-action.elapsed))
	for frame in 151:
		master._process(1.0/60)
		for child in master.get_children():
			if child is MasterSwordQi:
				child.set_process(false)
				child._process(1.0/60)
		await process_frame
		await RenderingServer.frame_post_draw
		if frames or frame in [20,32,39,44,50,60,75,100]: root.get_texture().get_image().save_png(output.path_join("frame_%03d.png" % frame))
	room.free()
	current_scene=null
	await process_frame
	await process_frame
	expect_save_untouched()
	finish("PHASE ONE QI RENDER")

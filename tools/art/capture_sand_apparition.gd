extends SceneTree
const OUT = "D:/HomingStar/homeing-star-test/artifacts/sandstorm-scorpion-study/apparition/"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.unfocusable = true
	root.position = Vector2i(-1500,-1500)
	root.size = Vector2i(1280,720)
	var tail_mode:=OS.get_cmdline_user_args().has("--tail")
	var output:=OUT if not tail_mode else OUT.get_base_dir()+"/tail_stab/"
	var fps:=60.0 if tail_mode else 30.0
	DirAccess.make_dir_recursive_absolute(output)
	var scene_path:="res://studies/sandstorm_scorpion/tail_stab.tscn" if tail_mode else "res://studies/sandstorm_scorpion/sand_apparition.tscn"
	var scene = load(scene_path).instantiate()
	root.add_child(scene)
	var shape = scene.get_node("PixelPreview/PixelCanvas/SandShape")
	shape.autoplay = false
	var telemetry:=[]
	for frame in range(265 if tail_mode else 133):
		shape.elapsed = frame/fps
		await process_frame
		await RenderingServer.frame_post_draw
		var error = root.get_texture().get_image().save_png(output+"frame_%03d.png"%frame)
		if error != OK:
			push_error("Frame export failed: "+str(error))
			quit(1)
			return
		if tail_mode:
			var positions:=[]
			for node in shape.mask_nodes: positions.append([node.position.x,node.position.y])
			telemetry.append({"t":shape.elapsed,"tip":[shape.tip.x,shape.tip.y],"parts":positions,"floor":shape.floor_y})
	if tail_mode:
		var file:=FileAccess.open(output+"motion.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(telemetry))
		file.close()
	print("Sand apparition capture: ",fps," FPS; action time 0..4.4; tail mode ",tail_mode)
	scene.queue_free()
	await process_frame
	quit()

extends "preview_sunken_cavern.gd"
## Native quarter-pixel camera sweep, old vs current material in memory only.

func run() -> void:
	use_memory_progress()
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	var level: Node2D=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	for i in 12: await physics_frame
	level.set_process(false)
	level.player.process_mode=Node.PROCESS_MODE_DISABLED
	level.player.visible=false
	level.drips.visible=false
	for layer in root.find_children("*","CanvasLayer",true,false): layer.visible=false
	level.camera.position_smoothing_enabled=false
	var materials: Array[ShaderMaterial]=[]
	for child in level.entrance_art.get_children():
		if child is CanvasItem and child.material is ShaderMaterial:
			var paint:=child.material as ShaderMaterial
			if paint.shader.resource_path.ends_with("timber_walkway.gdshader"):
				materials.append(paint)
	var current:=load("res://assets/levels/chapter_2_underwater/cavern/environment/west_market/timber_walkway.gdshader") as Shader
	var original:=Shader.new()
	original.code=FileAccess.get_file_as_string(output.path_join("old_timber.gdshader"))
	check(original.code.contains("depth/0.15+276.0"),"Comparison loads the actual previous timber shader")
	var raw:=Image.load_from_file(ProjectSettings.globalize_path("res://assets/levels/chapter_2_underwater/cavern/environment/west_market/broken_timber_walkway_2172x724.png"))
	var raw_texture:=ImageTexture.create_from_image(raw)
	var filtered:=load("res://assets/levels/chapter_2_underwater/cavern/environment/west_market/broken_timber_walkway_2172x724.png") as Texture2D
	check(not raw.has_mipmaps() and raw.get_width()==2172,"Comparison uses the original full-detail unmipped source")
	check(filtered.get_width()<=512 and filtered.get_image().has_mipmaps(),"Current runtime wood uses reduced detail and mipmaps")
	for version in ["before","after"]:
		for paint in materials:
			paint.shader=original if version=="before" else current
			paint.set_shader_parameter("timber_paint",raw_texture if version=="before" else filtered)
		for frame in 24:
			level.camera.position=Vector2(7640+frame*0.25,2930)
			level.camera.reset_smoothing()
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			var picture:=root.get_texture().get_image()
			var crop:=picture.get_region(Rect2i(400,240,320,42))
			crop.save_png(output.path_join("%s_%02d.png" % [version,frame]))
			if frame==0: picture.save_png(output.path_join(version+"_full.png"))
	check(materials.size()>100,"Camera sweep covers the shared floor material used throughout the map")
	await close_capture(level)

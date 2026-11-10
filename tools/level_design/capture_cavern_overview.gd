extends "preview_sunken_cavern.gd"
## Native high-resolution overview of the current art plus remaining graybox.


func run() -> void:
	use_memory_progress()
	# Set the internal viewport as well as the window: project defaults render
	# to 1280x720, so enlarging only the window would merely upscale the image.
	root.content_scale_size=Vector2i(3840,2304)
	root.size=Vector2i(3840,2304)
	var level: Node2D=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	for i in 12: await physics_frame
	level.set_process(false)
	level.player.process_mode=Node.PROCESS_MODE_DISABLED
	level.player.visible=false
	for layer in root.find_children("*","CanvasLayer",true,false): layer.visible=false
	level.camera.position_smoothing_enabled=false
	level.camera.limit_left=-20000
	level.camera.limit_top=-20000
	level.camera.limit_right=20000
	level.camera.limit_bottom=20000
	var viewport_size: Vector2=root.get_visible_rect().size
	var zoom:=minf((viewport_size.x-128)/level.bounds.size.x,(viewport_size.y-128)/level.bounds.size.y)
	level.camera.zoom=Vector2.ONE*zoom
	level.camera.position=level.bounds.get_center()
	level.camera.reset_smoothing()
	# A zoomed-out camera spans much more than the native parallax painting.
	# For this overview only, sample the deep layer as though each map point
	# were at a normal camera centre. Keep the rendering continuous instead
	# of clamping the lower half to the source image's last pixel row.
	var depth_shader:=load("res://assets/levels/chapter_2_underwater/cavern/environment/entrance/cavern_depth.gdshader") as Shader
	var overview_shader:=depth_shader.duplicate() as Shader
	var native_uv:="(world-vec2(0.0,deep_origin_y)-deep_parallax_offset)/deep_paint_size"
	var overview_uv:="(world-vec2(0.0,deep_origin_y)-(world-vec2(640.0,4200.0))*vec2(0.75,0.85))/deep_paint_size"
	check(overview_shader.code.contains(native_uv),"Overview recognizes the current deep-background mapping")
	overview_shader.code=overview_shader.code.replace(native_uv,overview_uv)
	for child in level.entrance_art.get_children():
		if child is CanvasItem and child.material is ShaderMaterial:
			var paint:=child.material as ShaderMaterial
			if paint.shader==depth_shader: paint.shader=overview_shader
	var palace:=level.entrance_art.get_node("DistantWaterPalace") as CanvasItem
	var palace_material:=palace.material as ShaderMaterial
	var palace_shader:=palace_material.shader.duplicate() as Shader
	palace_shader.code=palace_shader.code.replace("world-vec2(8832.0,4960.0)-parallax_offset","world-vec2(8832.0,4960.0)-(world-vec2(8832.0,4960.0))*vec2(0.85)")
	palace_material.shader=palace_shader
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_overview_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	var picture:=root.get_texture().get_image()
	var target:=output.path_join("sunken_cavern_current_overview.png")
	var result:=picture.save_png(target)
	check(result==OK and picture.get_width()>=3000,"Current full-map overview renders at native high resolution")
	var report={"image":target,"size":[picture.get_width(),picture.get_height()],
		"viewport":[viewport_size.x,viewport_size.y],"zoom":zoom,
		"scene":SCENE,"capture_type":"fixed-camera native overview; not a traversal test",
		"hud_hidden":true,"current_art_and_graybox":true,
		"deep_background_projection":"overview-only continuous normal-camera-centre sampling"}
	var file:=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if "--regions" in OS.get_cmdline_user_args():
		var reference := load("res://../homeing-star-test/tools/level_design/cavern_region_reference.gd").new() as Node2D
		reference.setup(picture,level.bounds,zoom,level.layout.mechanisms.echoes)
		var reference_layer := CanvasLayer.new()
		reference_layer.layer = 100
		reference_layer.add_child(reference)
		root.add_child(reference_layer)
		root.content_scale_size = Vector2i(4800,2560)
		root.size = Vector2i(4800,2560)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var annotated := root.get_texture().get_image()
		check(annotated.save_png(output.path_join("sunken_cavern_regions_a1_a27.png"))==OK,"Numbered region reference saved")
		reference_layer.queue_free()
	await close_capture(level)

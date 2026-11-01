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
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var output:=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_overview_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	var picture:=root.get_texture().get_image()
	var target:=output.path_join("sunken_cavern_current_overview.png")
	var result:=picture.save_png(target)
	check(result==OK and picture.get_width()>=3000,"Current full-map overview renders at native high resolution")
	var report={"image":target,"size":[picture.get_width(),picture.get_height()],
		"viewport":[viewport_size.x,viewport_size.y],"zoom":zoom,
		"scene":SCENE,"capture_type":"fixed-camera native overview; not a traversal test",
		"hud_hidden":true,"current_art_and_graybox":true}
	var file:=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	await close_capture(level)

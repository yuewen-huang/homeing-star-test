extends SceneTree
## Renders the whole 水下沉城 graybox (7680×4320) into a PNG at half scale (3840×2160).
## Run (not headless): godot --path <game> --script <this> -- <out.png>

const SCENE_PATH := "res://scenes/levels/chapter_2_underwater/chapter_2_underwater.tscn"
const SCALE := 0.5


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://chapter_2_underwater_overview.png"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(Vector2(7680, 4320) * SCALE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var level := (load(SCENE_PATH) as PackedScene).instantiate()
	viewport.add_child(level)
	for i in 3:
		await process_frame
	var hud := level.get_node_or_null("GrayboxHud")
	if hud:
		hud.visible = false
	var cam: Camera2D = level.camera
	cam.position_smoothing_enabled = false
	level.set_process(false)
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.zoom = Vector2(SCALE, SCALE)
	cam.position = Vector2(3840, 2160)
	cam.reset_smoothing()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var err := image.save_png(out)
	print("OVERVIEW saved %s (%s) err %d" % [out, image.get_size(), err])
	quit(0 if err == OK else 1)

extends SceneTree
## Native visual diagnostic: fixed camera and geometry, two moments of the drifting cloud field.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var sky_mode := "--sky-clouds" in OS.get_cmdline_user_args()
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save); real_save.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	var field := load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate() as SaltFieldPrototype
	root.add_child(field); current_scene = field
	field.set_physics_process(false)
	field.feet = Vector2(1800,120 if sky_mode else 900)
	field.exploration_camera_position = field.PROJECTION.project(field.feet)-Vector2(0,120)
	field._sync_view(0)
	await process_frame
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image()
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var prefix := "sky_clouds" if sky_mode else "salt_clouds"
	if not output.is_empty(): first.save_png(output.path_join(prefix+"_start.png"))
	await create_timer(8.0).timeout
	await RenderingServer.frame_post_draw
	var later := root.get_texture().get_image()
	if not output.is_empty(): later.save_png(output.path_join(prefix+"_after_8s.png"))
	# Sample the ground patch or sky band while geometry and camera remain fixed.
	var difference := 0.0
	var samples := 0
	for y in range(120 if sky_mode else 360,350 if sky_mode else 620,8):
		for x in range(40,1200 if sky_mode else 300,8):
			difference += absf(first.get_pixel(x,y).get_luminance()-later.get_pixel(x,y).get_luminance())
			samples += 1
	var average := difference/samples
	print("SKY CLOUD TEMPORAL LUMINANCE DIFFERENCE: " if sky_mode else "CLOUD SHADOW TEMPORAL LUMINANCE DIFFERENCE: ",average)
	field.free(); current_scene = null
	await process_frame
	quit(0 if average>0.002 else 1)

extends SceneTree
## Compare authored and baked pixels at both wall edges with deterministic lighting/pose.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok: failures += 1

func picture(baked: bool,point: Vector2,label_: String) -> Image:
	var field: Node2D = load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate()
	field.use_baked_boundary = baked
	root.add_child(field); current_scene = field
	field.process_mode = Node.PROCESS_MODE_DISABLED
	field.ground_layer.material.set_shader_parameter("cloud_strength",0.0)
	field.get_node("Environment/Backdrop/OuterGround").material.set_shader_parameter("cloud_strength",0.0)
	for patch in field.get_node("Environment/WorksiteDetails").find_children("GroundMarks","MeshInstance2D",true,false):
		patch.material.set_shader_parameter("cloud_strength",0.0)
	field.feet = point; field._sync_view(0)
	# Compare the baked world-pixel grid at its original raster phase. A fractional
	# camera would resample nearest-filtered pages a second time and add 1px aliasing.
	field.camera.position = field.camera.position.round()
	check((field.baked_boundary!=null)==baked,"Requested baked mode installed: %s" % baked)
	if baked and field.baked_boundary:
		var single: MeshInstance2D = field.baked_boundary.get_node_or_null("BoundarySingleDraw")
		check(single!=null and single.mesh.get_surface_count()==1,"Boundary uses one mesh surface and one shared color atlas")
		check(field.baked_boundary.find_children("*","Sprite2D",true,false).is_empty(),"No per-page boundary sprites remain in atlas mode")
	await process_frame; await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not output.is_empty(): image.save_png(output.path_join(label_+".png"))
	field.free(); current_scene = null
	await process_frame
	return image

func run() -> void:
	if DisplayServer.get_name()=="headless": print("SKIP visual baked-boundary comparison in headless mode"); quit(); return
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var real_save := root.get_node("SaveProgress"); root.remove_child(real_save); real_save.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	for side in [40,7160]:
		for depth in [495,1075,1655]:
			var label_ := "bake_compare_%d_%d" % [side,depth]
			var limits := SaltFieldPerimeter.x_limits(depth)
			var point := Vector2(limits.x if side==40 else limits.y,depth)
			var original := await picture(false,point,label_+"_original")
			var baked := await picture(true,point,label_+"_baked")
			var error := 0.0
			# Exclude animated HUD counters; world geometry and lighting are frozen.
			var count := 0
			for y in range(300,640,2):
				for x in range(20,1260,2):
					var a := original.get_pixel(x,y); var b := baked.get_pixel(x,y)
					error += (absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0; count += 1
			var average := error/count
			check(average<0.015,"Authored/baked visual difference %.5f at wall %d depth %d" % [average,side,depth])
	await process_frame
	print("BAKED BOUNDARY: ",failures," failures")
	quit(1 if failures else 0)

extends SceneTree
## Native render bake: colour + 16-bit object-depth pages preserve the original occlusion.
const OUTPUT := "res://assets/sideview/environment/chapter_2_salt/baked_boundary/"
const SOURCE := "res://scenes/sideview/chapter_2_salt_field.tscn"
const PAGE_SIZE := 1024
var viewport: SubViewport
var stage: Node2D
var sprites: Array[CanvasItem] = []

func _initialize() -> void: run.call_deferred()

func source_hashes() -> Dictionary:
	var result := {}
	for path in [SOURCE,"res://scenes/sideview/chapter_2_salt_environment.tscn",
		"res://scripts/sideview/salt_field_perimeter.gd",
		"res://assets/sideview/environment/chapter_2_salt/salt_outcrop_1.png",
		"res://assets/sideview/environment/chapter_2_salt/salt_outcrop_2.png",
		"res://assets/sideview/environment/chapter_2_salt/salt_outcrop_3.png",
		"res://assets/sideview/environment/chapter_2_salt/salt_boundary_v1.png"]:
		result[path] = FileAccess.get_md5(path)
	for name_ in DirAccess.get_files_at("res://assets/sideview/environment/chapter_2_salt/layout_wide"):
		if name_.begins_with("north_") and name_.ends_with(".tres"):
			var path := "res://assets/sideview/environment/chapter_2_salt/layout_wide/"+name_
			result[path] = FileAccess.get_md5(path)
	return result

func capture(origin: Vector2) -> Image:
	viewport.canvas_transform = Transform2D(0,-origin)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var sources := source_hashes()
	var source: Node2D = load(SOURCE).instantiate()
	var boundary := source.get_node("Environment/Boundary")
	viewport = SubViewport.new(); viewport.size = Vector2i(PAGE_SIZE,PAGE_SIZE)
	viewport.transparent_bg = true; viewport.disable_3d = true; viewport.world_2d = World2D.new()
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	stage = Node2D.new(); stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; viewport.add_child(stage)
	# Match authored tree order for equal-depth fragments: wall slices precede rocks.
	var items := boundary.find_children("*","MeshInstance2D",true,false)
	items.append_array(boundary.find_children("SaltBank_*","Sprite2D",true,false))
	var bounds := Rect2()
	var first := true
	for item: Node2D in items:
		var rect: Rect2
		if item is Sprite2D: rect = item.get_rect()
		else:
			var aabb: AABB = item.mesh.get_aabb()
			rect = Rect2(aabb.position.x,aabb.position.y,aabb.size.x,aabb.size.y)
		var transform_ := item.get_global_transform()
		var world_rect := transform_*rect
		bounds = world_rect if first else bounds.merge(world_rect); first = false
		var copy := item.duplicate() as Node2D
		copy.set_script(null); copy.transform = transform_
		stage.add_child(copy); sprites.append(copy)
	var origins: Array[Vector2] = []
	for y in range(floori(bounds.position.y/PAGE_SIZE),ceili(bounds.end.y/PAGE_SIZE)):
		for x in range(floori(bounds.position.x/PAGE_SIZE),ceili(bounds.end.x/PAGE_SIZE)):
			origins.append(Vector2(x,y)*PAGE_SIZE)
	var pages: Array[Dictionary] = []
	for i in origins.size():
		var image := await capture(origins[i])
		var used := image.get_used_rect()
		if not used.has_area(): continue
		var path := OUTPUT+"color_%02d.png" % i
		var result := image.get_region(used).save_png(path)
		if result!=OK: quit(result); return
		pages.append({"color":path,"depth":OUTPUT+"depth_%02d.png" % i,"x":origins[i].x+used.position.x,
			"y":origins[i].y+used.position.y,"origin":i,"crop":[used.position.x,used.position.y,used.size.x,used.size.y]})
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item; render_mode unshaded; uniform float object_depth; void fragment(){ if(texture(TEXTURE,UV).a<0.02)discard; float value=floor(object_depth+0.5); COLOR=vec4(floor(value/256.0)/255.0,mod(value,256.0)/255.0,0.0,1.0); }'
	for item in sprites:
		var material_ := ShaderMaterial.new(); material_.shader = shader
		material_.set_shader_parameter("object_depth",float(item.z_index)); item.material = material_
	for page in pages:
		var image := await capture(origins[page.origin])
		var crop: Array = page.crop
		var result := image.get_region(Rect2i(crop[0],crop[1],crop[2],crop[3])).save_png(page.depth)
		if result!=OK: quit(result); return
		page.erase("origin"); page.erase("crop")
	if source_hashes()!=sources:
		push_error("Source changed during bake. Saved authoring is intact; rerun after saving."); quit(1); return
	var file := FileAccess.open(OUTPUT+"manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"sources":sources,"pages":pages},"\t")); file.close()
	print("BOUNDARY BAKE: ",items.size()," items -> ",pages.size()," colour/depth pages")
	source.free(); viewport.free()
	await process_frame
	quit()

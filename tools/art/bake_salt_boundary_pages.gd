extends SceneTree
## Native render bake: colour + 16-bit object-depth pages preserve the original occlusion.
const OUTPUT := "res://assets/sideview/environment/chapter_2_salt/baked_boundary/"
const SOURCE := "res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn"
const PAGE_SIZE := 1024
var viewport: SubViewport
var stage: Node2D
var sprites: Array[CanvasItem] = []

func pack_atlas(pages: Array[Dictionary]) -> Dictionary:
	# Sparse world quads share one texture. Avoid allocating the empty map middle.
	var ordered := pages.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.crop_size[1]>b.crop_size[1])
	# Pages are at most 1024 px wide. Balance three padded columns by height;
	# this avoids the large empty shelves left by the narrow north-wall strips.
	var heights := [1,1,1]
	var used_width := 0
	for page in ordered:
		var size := Vector2i(page.crop_size[0],page.crop_size[1])
		var column := 0
		for index in range(1,3):
			if heights[index]<heights[column]: column = index
		var cursor := Vector2i(column*(PAGE_SIZE+2)+1,heights[column])
		page.atlas_rect = [cursor.x,cursor.y,size.x,size.y]
		heights[column] += size.y+2
		used_width = maxi(used_width,cursor.x+size.x+1)
	var dimensions := Vector2i(used_width,int(heights.max()))
	if dimensions.x>4096 or dimensions.y>4096:
		push_error("Boundary atlas exceeds its texture budget")
		return {}
	var color := Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	var depth := Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	color.fill(Color.TRANSPARENT)
	depth.fill(Color.TRANSPARENT)
	for page in pages:
		var rect: Array = page.atlas_rect
		var at := Vector2i(rect[0],rect[1])
		var color_page := Image.load_from_file(page.color)
		var depth_page := Image.load_from_file(page.depth)
		color.blit_rect(color_page,Rect2i(Vector2i.ZERO,color_page.get_size()),at)
		depth.blit_rect(depth_page,Rect2i(Vector2i.ZERO,depth_page.get_size()),at)
		page.erase("crop_size")
	var color_error := color.save_png(OUTPUT+"boundary_atlas.png")
	var depth_error := depth.save_png(OUTPUT+"boundary_depth_atlas.png")
	if color_error!=OK or depth_error!=OK:
		push_error("Could not save boundary atlases: %d / %d" % [color_error,depth_error])
		return {}
	return {"color":OUTPUT+"boundary_atlas.png","depth":OUTPUT+"boundary_depth_atlas.png","size":[dimensions.x,dimensions.y]}

func _initialize() -> void: run.call_deferred()

func source_hashes() -> Dictionary:
	var result := {}
	for path in [SOURCE,"res://scenes/levels/chapter_2_salt/chapter_2_salt_environment.tscn",
		"res://scripts/levels/chapter_2_salt/salt_field_perimeter.gd",
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
		page.crop_size = [crop[2],crop[3]]
	if source_hashes()!=sources:
		push_error("Source changed during bake. Saved authoring is intact; rerun after saving."); quit(1); return
	var atlas := pack_atlas(pages)
	if atlas.is_empty(): quit(1); return
	var file := FileAccess.open(OUTPUT+"manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":2,"sources":sources,"pages":pages,"atlas":atlas},"\t")); file.close()
	print("BOUNDARY BAKE: ",items.size()," items -> ",pages.size()," sparse quads, one colour/depth atlas ",atlas.size)
	source.free(); viewport.free()
	await process_frame
	quit()

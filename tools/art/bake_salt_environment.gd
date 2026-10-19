extends SceneTree
## One-time authoring export. Runtime never invokes this or overwrites hand-placed props.
const DEST := "res://scenes/levels/chapter_2_salt/chapter_2_salt_environment.tscn"
const GROUND := preload("res://scripts/levels/chapter_2_salt/salt_field_ground.gd")
const BOUNDARY := preload("res://scripts/levels/chapter_2_salt/salt_field_boundary.gd")
const CLOUDS := preload("res://scripts/levels/chapter_2_salt/chapter_2_salt_environment.gd")
const PROP_DEPTH := preload("res://scripts/levels/chapter_2_salt/salt_field_prop_depth.gd")
var environment: Node2D

func _initialize() -> void: bake.call_deferred()

func sprite(parent: Node,name_: String,texture: Texture2D,position_: Vector2,scale_: Vector2,flip := false) -> Sprite2D:
	var result := Sprite2D.new()
	result.name = name_; result.texture = texture; result.centered = false
	result.position = position_; result.scale = scale_; result.flip_h = flip
	parent.add_child(result)
	return result

func fill(parent: Node,name_: String,rect: Rect2,color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.name = name_
	polygon.polygon = PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	polygon.color = color
	polygon.set_meta("_edit_lock_",true)
	parent.add_child(polygon)

func own(node: Node) -> void:
	for child in node.get_children():
		child.owner = environment
		own(child)

func bake() -> void:
	if FileAccess.file_exists(DEST):
		push_error("Refusing to overwrite authored environment: "+DEST); quit(1); return
	environment = Node2D.new(); environment.name = "Environment"
	environment.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(environment)
	var backdrop := Node2D.new(); backdrop.name = "Backdrop"; backdrop.z_index = -20
	environment.add_child(backdrop)
	var sky: Texture2D = load("res://assets/sideview/environment/chapter_2_salt/salt_clear_sky_v1.png")
	fill(backdrop,"OutsideBase",Rect2(-6000,-4000,15600,10000),Color("e7ede9"))
	fill(backdrop,"UpperSky",Rect2(-6000,-4000,15600,3660),sky.get_image().get_pixel(600,0))
	for i in range(-4,8):
		var panorama := sprite(backdrop,"Sky_%02d" % (i+4),sky,Vector2(i*1020,-340),Vector2.ONE*0.85,posmod(i,2)==1)
		panorama.set_meta("_edit_lock_",true)
	# Bake the mirrored outer terrain into one mesh instead of transient draw commands.
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	for row in 20:
		for column in 23:
			var origin := Vector2(-3150+column*450,row*120)
			var base := vertices.size()
			for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var point: Vector2 = origin+uv*Vector2(450,120)
				vertices.append(Vector3(point.x,point.y,0))
				uvs.append(GROUND.tile_uv(column-7,row,uv))
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var outer := MeshInstance2D.new(); outer.name = "OuterGround"; outer.z_index = 10
	outer.mesh = mesh; outer.texture = GROUND.TILE_TEXTURE
	var palette := ShaderMaterial.new(); palette.shader = GROUND.PALETTE; outer.material = palette
	outer.set_meta("_edit_lock_",true); backdrop.add_child(outer)
	var clouds := CLOUDS.new(); clouds.name = "SkyClouds"; backdrop.add_child(clouds)
	var generated := GROUND.new(); environment.add_child(generated)
	var ground := MeshInstance2D.new(); ground.name = "Ground"; ground.z_index = -5
	ground.mesh = generated.mesh; ground.texture = generated.texture; ground.material = generated.material
	ground.set_meta("_edit_lock_",true); environment.add_child(ground)
	generated.free()
	var boundary := BOUNDARY.new(); boundary.name = "Boundary"; environment.add_child(boundary)
	boundary.build_at_runtime = false
	for rock in boundary.outcrops: rock.set_script(PROP_DEPTH)
	var old_coast := boundary.get_node("SouthCoast")
	var sea := old_coast.get_child(0).duplicate()
	old_coast.free()
	var coast := Node2D.new(); coast.name = "SouthCoast"; coast.z_index = -4
	boundary.add_child(coast); coast.add_child(sea)
	for x in range(-3600,7200,600):
		sprite(coast,"Shore_%02d" % ((x+3600)/600),BOUNDARY.COAST_TEXTURE,Vector2(x,1048),Vector2.ONE,posmod(x/600,2)==1)
	own(environment)
	var scene := PackedScene.new()
	var error := scene.pack(environment)
	if error == OK: error = ResourceSaver.save(scene,DEST)
	print("AUTHORED ENVIRONMENT EXPORT: ",error,"; editable rocks: ",boundary.outcrops.size())
	environment.free()
	quit(error)

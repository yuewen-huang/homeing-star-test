extends SceneTree
const OUT := "res://assets/levels/chapter_2_salt/environment/layout_wide/"
const GROUND := preload("res://scripts/levels/chapter_2_salt/salt_field_ground.gd")
const BOUNDARY := preload("res://scripts/levels/chapter_2_salt/salt_field_boundary.gd")
func _initialize() -> void: run.call_deferred()
func save_(resource: Resource,name_: String) -> void:
	var error := ResourceSaver.save(resource,OUT+name_+".tres")
	if error!=OK: push_error("Mesh export failed"); quit(error)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var ground := GROUND.new(); ground._ready(); save_(ground.mesh,"ground"); ground.free()
	var boundary := BOUNDARY.new()
	for x in range(0,7200,720): boundary._add_section(Vector2(x,60),Vector2(x+720,60),64)
	for i in boundary.get_child_count(): save_(boundary.get_child(i).get_child(0).mesh,"north_%02d"%i)
	boundary.free()
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	for row in 20:
		for column in 31:
			var origin := Vector2(-3150+column*450,row*120)
			var base := vertices.size()
			for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var point: Vector2 = origin+uv*Vector2(450,120)
				vertices.append(Vector3(point.x,point.y,0)); uvs.append(GROUND.tile_uv(column-7,row,uv))
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); save_(mesh,"outer_ground")
	var ambient := load("res://scenes/levels/chapter_2_salt/chapter_2_salt_ambient.tscn").instantiate() as Node2D
	var details: MeshInstance2D = ambient.get_node("StaticScatter")
	arrays=details.mesh.surface_get_arrays(0); vertices=arrays[Mesh.ARRAY_VERTEX]
	var placements: Array = details.get_meta("placements")
	for i in placements.size():
		var foot: Vector2=placements[i].foot
		var s:=SaltFieldProjection.depth_scale(foot.y)
		var old_x:=1800+(foot.x-1800)*s
		for j in 4: vertices[i*4+j].x+=old_x
	arrays[Mesh.ARRAY_VERTEX]=vertices
	mesh=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); save_(mesh,"ambient")
	ambient.free()
	print("WIDE MESHES: ground, outer terrain, 10 north sections and preserved ambient quads")
	quit()

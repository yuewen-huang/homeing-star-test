extends SceneTree
const DEST := "res://scenes/sideview/chapter_2_salt_ambient.tscn"
const PATH := "res://assets/sideview/environment/chapter_2_salt/ambient/"
const PROJECTION := preload("res://scripts/sideview/salt_field_projection.gd")
const CONTROLLER := preload("res://scripts/sideview/salt_field_ambient.gd")
const CRITTER := preload("res://scripts/sideview/salt_field_critter.gd")
var rng := RandomNumberGenerator.new()
var field: Node2D
var occupied: Array[Vector2] = []

func _initialize() -> void: run.call_deferred()
func point(shore := false) -> Vector2:
	for attempt in 400:
		var candidate := Vector2(rng.randf_range(110,3490),rng.randf_range(1360 if shore else 200,1700))
		if candidate.distance_to(field.SPAWN)<110 or candidate.distance_to(field.RETURN_POINT)<115: continue
		var valid := true
		for pile in field.piles:
			if pile.footprint().grow(65).has_point(candidate): valid = false; break
		for previous in occupied:
			if previous.distance_to(candidate)<65: valid = false; break
		if valid: occupied.append(candidate); return candidate
	push_error("No clear ambient placement found"); quit(1); return Vector2(1800,900)

func run() -> void:
	if FileAccess.file_exists(DEST): push_error("Refusing to replace authored ambient scene"); quit(1); return
	rng.seed = 20261017
	field = load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate()
	field._build_piles()
	var atlas: Texture2D = load(PATH+"ambient_atlas.png")
	if atlas==null: quit(1); return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(PATH+"atlas_manifest.json"))
	var scene := Node2D.new(); scene.name = "AmbientDetails"; scene.set_script(CONTROLLER)
	scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	var kinds := ["starfish","plank","stone_1","stone_2","stone_3","crystal"]
	var counts := [20,16,24,16,24,24]
	var widths := [24.0,55.0,32.0,20.0,32.0,28.0]
	var placements := []
	for k in kinds.size():
		var spec = manifest.static[kinds[k]]
		var b: Array = spec.bounds
		var cell := Vector2i(int(spec.cell)%10,int(spec.cell)/10)*100
		for i in counts[k]:
			var foot := point(k==0 or (k==1 and i%2==0))
			var size: float = widths[k]/float(b[2])*rng.randf_range(0.8,1.2)*PROJECTION.depth_scale(foot.y)
			var turn := rng.randf_range(-0.35,0.35) if k<2 else 0.0
			var base := vertices.size()
			for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var local: Vector2 = (uv*100-Vector2(float(b[0])+float(b[2])*0.5,float(b[1])+float(b[3])))*size
				var projected := PROJECTION.project(foot)+local.rotated(turn)
				vertices.append(Vector3(projected.x,projected.y,0))
				uvs.append((Vector2(cell)+uv*100)/Vector2(1000,300))
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
			placements.append({"kind":kinds[k],"foot":foot})
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var details := MeshInstance2D.new(); details.name = "StaticScatter"; details.mesh = mesh; details.texture = atlas; details.z_index = -2
	details.set_meta("placements",placements); scene.add_child(details); details.owner = scene
	var wildlife := Node2D.new(); wildlife.name = "Wildlife"; scene.add_child(wildlife); wildlife.owner = scene
	var animal_kinds := ["fish","jijuxie","pangxie","woniu"]
	for species in animal_kinds.size():
		var spec = manifest.animals[animal_kinds[species]]
		var frames := SpriteFrames.new(); frames.remove_animation(&"default"); frames.add_animation(&"move")
		frames.set_animation_speed(&"move",10); frames.set_animation_loop(&"move",true)
		for f in spec.frames:
			var texture := AtlasTexture.new(); texture.atlas = atlas
			texture.region = Rect2(Vector2(int(f.cell)%10,int(f.cell)/10)*100,Vector2(100,100))
			frames.add_frame(&"move",texture,float(f.seconds)*10.0)
		for i in 4:
			var creature := AnimatedSprite2D.new(); creature.set_script(CRITTER)
			creature.name = animal_kinds[species]+"_%d" % (i+1); creature.species = species
			creature.sprite_frames = frames; creature.animation = &"move"
			creature.centered = false; creature.offset = Vector2(-50,-float(spec.foot_y))
			var foot := point(species==0)
			creature.position = PROJECTION.project(foot); creature.z_index = roundi(foot.y)
			creature.scale = Vector2.ONE*[0.38,0.32,0.34,0.30][species]*PROJECTION.depth_scale(foot.y)
			wildlife.add_child(creature); creature.owner = scene
	var packed := PackedScene.new(); var error := packed.pack(scene)
	if error==OK: error = ResourceSaver.save(packed,DEST)
	print("AMBIENT SCENE ",placements.size()," static items in one mesh; ",wildlife.get_child_count()," critters; result ",error)
	field.free(); scene.free(); quit(error)

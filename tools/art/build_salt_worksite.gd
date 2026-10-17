extends SceneTree
const DEST := "res://scenes/sideview/chapter_2_salt_worksite.tscn"
const ART := "res://assets/sideview/environment/chapter_2_salt/worksite/"
const PATCH := preload("res://scripts/sideview/salt_worksite_patch.gd")
const DEPTH := preload("res://scripts/sideview/salt_field_prop_depth.gd")
func _initialize() -> void: run.call_deferred()
func own(node: Node,owner_: Node) -> void:
	for child in node.get_children(): child.owner=owner_; own(child,owner_)
func run() -> void:
	if FileAccess.file_exists(DEST): push_error("Refusing to replace authored worksite"); quit(1); return
	var scene := Node2D.new(); scene.name="WorksiteDetails"; scene.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(scene)
	var material_ := ShaderMaterial.new(); material_.shader=load(ART+"worksite_ground.gdshader")
	var names := ["LoadingPoint","RakingBed","BrineIntake"]
	var centers := [Vector2(760,1480),Vector2(3350,875),Vector2(5650,1500)]
	var files := ["loading_ground","raked_bed","shallow_brine"]
	var widths := [360.0,420.0,520.0]
	for i in 3:
		var group := Node2D.new(); group.name=names[i]; scene.add_child(group)
		var patch := MeshInstance2D.new(); patch.set_script(PATCH); patch.name="GroundMarks"
		patch.texture=load(ART+files[i]+".png"); patch.world_width=widths[i]
		patch.position=SaltFieldProjection.project(centers[i]); patch.z_index=-4; patch.material=material_
		group.add_child(patch)
		if i!=1:
			var prop := Sprite2D.new(); prop.name="WoodenTrough"; prop.texture=load(ART+"wooden_trough.png")
			prop.centered=false; prop.offset=Vector2(-prop.texture.get_width()*0.5,-prop.texture.get_height())
			var foot: Vector2 = centers[i]+Vector2(-55,-18) if i==0 else centers[i]+Vector2(215,-48)
			prop.position=SaltFieldProjection.project(foot); prop.scale=Vector2.ONE*1.35*SaltFieldProjection.depth_scale(foot.y)
			prop.set_script(DEPTH); group.add_child(prop)
			if i==0:
				var rake := Sprite2D.new(); rake.name="SaltRake"; rake.texture=load(ART+"salt_rake.png")
				rake.centered=false; rake.offset=Vector2(-rake.texture.get_width()*0.5,-rake.texture.get_height())
				foot=centers[i]+Vector2(55,22); rake.position=SaltFieldProjection.project(foot)
				rake.scale=Vector2.ONE*SaltFieldProjection.depth_scale(foot.y); rake.set_script(DEPTH); group.add_child(rake)
	own(scene,scene)
	var packed := PackedScene.new(); var error := packed.pack(scene)
	if error==OK: error=ResourceSaver.save(packed,DEST)
	print("WORKSITE SCENE: ",error)
	scene.free(); quit(error)

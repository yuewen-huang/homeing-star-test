extends SceneTree
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config=ConfigFile.new(); _loaded=true
	func save_progress() -> bool: return true
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("OK " if ok else "FAIL ",message)
func capture(label_: String) -> void:
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_+".png"))==OK,"Capture "+label_)
func run() -> void:
	var old:=root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save:=MemorySave.new(); save.name="SaveProgress"; root.add_child(save)
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":2,"dug":[4,27]})
	var field:=load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate() as Chapter2SaltField
	root.add_child(field); current_scene=field; field.set_physics_process(false)
	check(field.piles.size()==56 and field.state.boss_pile==2 and field.piles[4].excavated and field.piles[27].excavated and not field.piles[28].excavated,"Legacy 28-heap saves retain the hidden core and dug IDs while adding new heaps")
	check(field.baked_boundary!=null,"Wider authored reefs use the updated baked boundary")
	var all_reachable:=true
	var nonoverlap:=true
	for i in field.piles.size():
		var pile:=field.piles[i]
		all_reachable=all_reachable and SaltFieldPerimeter.clamp_walker(pile.ground_position+Vector2(0,42)).is_equal_approx(pile.ground_position+Vector2(0,42))
		for j in range(i+1,field.piles.size()):
			nonoverlap=nonoverlap and not pile.footprint().grow(16).intersects(field.piles[j].footprint().grow(16))
	check(all_reachable and nonoverlap,"All 56 heap footprints are separated and retain excavation approaches")
	var worksite:=field.get_node("Environment/WorksiteDetails")
	check(worksite.get_child_count()==3 and worksite.find_children("GroundMarks","MeshInstance2D",true,false).size()==3,"Three painted worksite ground patches are saved in an editable scene")
	check(worksite.find_children("*","CollisionObject2D",true,false).is_empty(),"Shallow marks and low props leave the exploration routes open")
	for label_ in ["LoadingPoint","RakingBed","BrineIntake"]:
		var patch: MeshInstance2D=worksite.get_node(label_+"/GroundMarks")
		check(patch.mesh!=null and patch.texture!=null and patch.z_index==-4,"Painted "+label_+" is projected above the floor and below actors")
		field.feet=SaltFieldProjection.unproject(patch.global_position)+Vector2(0,150)
		field.exploration_camera_position=SaltFieldProjection.project(field.feet)-Vector2(0,120)
		field._sync_view(0)
		await capture("salt_worksite_"+label_)
	field.overview=true; field._sync_view(0); await capture("salt_wide_worksite_overview")
	field.free(); current_scene=null; await process_frame
	print("SALT WIDE WORKSITE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

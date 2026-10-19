extends SceneTree
## Exercise the real swept walker against the authored side curves.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func run() -> void:
	var old := root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	var field := load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate() as SaltFieldPrototype
	root.add_child(field); current_scene = field; field.set_physics_process(false)
	for y in [60,120,180,1670,1760,1800]:
		check(SaltFieldPerimeter.inset(0,y)==0 and SaltFieldPerimeter.inset(1,y)==0,"North/south joins retain original side coordinates at depth %d" % y)
	check(SaltFieldPerimeter.clamp_walker(field.SPAWN)==field.SPAWN and SaltFieldPerimeter.clamp_walker(field.RETURN_POINT)==field.RETURN_POINT,"Spawn and return gate remain in open walking space")
	for side in 2:
		for depth in [350,440,700,850,1075,1200,1390,1550]:
			var limits := SaltFieldPerimeter.x_limits(depth)
			var edge := limits.x if side==0 else limits.y
			var direction := -1.0 if side==0 else 1.0
			field.feet = Vector2(edge-direction*30,depth)
			field._move_feet(Vector2(direction*500,0))
			check(is_equal_approx(field.feet.x,edge),"Swept walk/skill displacement stops at actual side %d depth %d" % [side,depth])
			field._move_feet(Vector2(0,-100))
			limits = SaltFieldPerimeter.x_limits(field.feet.y)
			check(field.feet.x>=limits.x-0.01 and field.feet.x<=limits.y+0.01,"Following the curved edge stays inside side %d depth %d" % [side,depth])
	var reachable := true
	for pile in field.piles:
		var inspect := pile.ground_position+Vector2(0,42)
		reachable = reachable and SaltFieldPerimeter.clamp_walker(inspect).is_equal_approx(inspect)
	check(reachable,"Every salt heap retains its front excavation approach")
	var boundary: Node = load("res://scenes/sideview/chapter_2_salt_environment.tscn").instantiate().get_node("Boundary")
	# Only the north wall remains; the saved side reefs retain the terrain silhouette.
	var north_only := true
	var count := 0
	for section in boundary.get_children():
		if not String(section.name).begins_with("Wall_"): continue
		var index := String(section.name).trim_prefix("Wall_").to_int()
		north_only = north_only and index<10
		count += 1
		for strip in section.get_children():
			var vertices: PackedVector3Array = strip.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in 2:
				var point := SaltFieldProjection.unproject(Vector2(vertices[i].x,vertices[i].y))
				north_only = north_only and absf(point.y-60)<0.02
	check(north_only and count==10,"Authored walls cover the wider north edge; no side walls")
	boundary.get_parent().free()
	field.free(); current_scene = null
	await process_frame
	print("SALT IRREGULAR SIDES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

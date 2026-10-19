extends SceneTree
class Field extends Node2D:
	var feet := Vector2.ZERO
	var piles: Array = []
class Pile extends RefCounted:
	var excavated := false
	func footprint() -> Rect2: return Rect2(1780,840,90,120)
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func run() -> void:
	var ambient: Node2D = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_ambient.tscn").instantiate()
	ambient.process_mode = Node.PROCESS_MODE_DISABLED; root.add_child(ambient)
	var field := Field.new(); root.add_child(field); ambient.bind_field(field)
	check(ambient.get_node("StaticScatter").get_meta("placements").size()==124,"One static mesh contains all six decor kinds and 124 placements")
	check(ambient.get_node("StaticScatter").mesh.get_surface_count()==1,"Static dressing uses one atlas and one surface")
	var creatures := ambient.get_node("Wildlife").get_children()
	check(creatures.size()==16,"Four harmless individuals from each of four authored species")
	for animal in creatures:
		animal.feet = Vector2(1800,900); field.feet = Vector2(1700,900)
		animal.decision_time = 0; animal.fleeing = false
		var before: float = animal.feet.distance_to(field.feet)
		for i in 8: animal.advance(0.1)
		check(animal.fleeing and animal.feet.distance_to(field.feet)>before+10,"Approach makes %s move away" % animal.name)
		field.feet = Vector2(3000,1600)
		for i in 30: animal.advance(0.1)
		check(not animal.fleeing,"Distant %s calms down and resumes wandering" % animal.name)
		check(animal.find_children("*","CollisionObject2D",true,false).is_empty() and not animal.is_in_group("enemies"),"Ambient %s has no combat bodies or enemy group" % animal.name)
	var crab = creatures[8]
	crab.feet = Vector2(7110,1710); field.feet = Vector2(7000,1600); crab.decision_time = 0
	var remains_inside := true
	for i in 120:
		crab.advance(0.1)
		remains_inside = remains_inside and crab.AREA.has_point(crab.feet)
	check(remains_inside,"Flee steering stays within the map, including the near-right corner")
	field.piles = [Pile.new()]; crab.feet = Vector2(1745,900); field.feet = Vector2(1660,900); crab.decision_time = 0
	var avoids_heap := true
	for i in 120:
		crab.advance(0.1)
		avoids_heap = avoids_heap and not field.piles[0].footprint().grow(12).has_point(crab.feet)
	check(avoids_heap,"Wandering/fleeing does not pass through intact salt heaps")
	ambient.free()
	field.free()
	await process_frame
	print("SALT AMBIENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

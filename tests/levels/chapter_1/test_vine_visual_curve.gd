extends SceneTree
const CurveModel := preload("res://scripts/sideview/vine_visual_curve.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1
func _initialize() -> void:
	var curve = CurveModel.new()
	var root_error := 0.0
	var hand_error := 0.0
	var max_bow := 0.0
	var max_tail := 0.0
	for tick in 1200:
		var angle := sin(float(tick)/60.0*2.0)*0.8
		curve.advance(1.0/60,angle,800,300,true)
		root_error = maxf(root_error,curve.point(0,800,300,true).length())
		hand_error = maxf(hand_error,(curve.point(300,800,300,true)-Vector2(0,300)).length())
		max_bow = maxf(max_bow,absf(curve.bow))
		max_tail = maxf(max_tail,absf(curve.tail))
	check(root_error < 0.001 and hand_error < 0.001,"animated root and occupied grip remain exactly pinned")
	check(max_bow > 0.1 and max_bow <= 5.4,"loaded section has restrained single bow")
	check(max_tail > 10 and max_tail <= 75,"free tail trails swing without unbounded whip")
	var derivative_left := (curve.point(300,800,300,true)-curve.point(299.9,800,300,true))/0.1
	var derivative_right := (curve.point(300.1,800,300,true)-curve.point(300,800,300,true))/0.1
	check(derivative_left.distance_to(derivative_right)<0.02,"curve tangent remains continuous at hand")
	curve.advance(0.5,0.8,800,300,true)
	check(is_finite(curve.bow) and is_finite(curve.tail) and absf(curve.tail)<=75,"long render frame stays bounded")
	var old_tip: Vector2 = curve.point(800,800,300,true)
	curve.advance(1.0/60,0.8,800,800,false)
	check(old_tip.distance_to(curve.point(800,800,800,false)) < 10,"release relaxes trailing tail without snapping straight in one frame")
	curve.reset()
	check(curve.bow == 0 and curve.tail == 0,"respawn reset clears trailing deformation")
	for tick in 600: curve.advance(1.0/60,0,800,800,false)
	check(absf(curve.bow)<0.001 and absf(curve.tail)<0.001,"stationary unloaded vine settles straight")
	print("VINE VISUAL CURVE: ",failures," failures")
	quit(0 if failures == 0 else 1)

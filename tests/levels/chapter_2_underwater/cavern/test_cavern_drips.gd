extends "../../../support/harness.gd"
## Ambient topology/density/lifecycle review. Camera probes are not a route tour.

const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
var level: Node2D
var fx: Node2D
var output: String
var captured: Dictionary = {}
var frames := 0
var observations: Array = []


func run() -> void:
	use_memory_progress()
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_drips_20261101")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	fx=level.drips
	fx.set_timing_seed(4821)
	for i in 12: await process_frame
	check(fx.sources.size()>30,"Ceilings and beam undersides supply sources throughout the map")
	var dry_sources:=0
	var wet_sources:=0
	var submerged:=0
	var unanchored:=0
	for site in fx.sources:
		if site.wet: wet_sources+=1
		else: dry_sources+=1
		if absf(float(site.origin.y)-float(site.physical.y))>34: unanchored+=1
		for pool in level.layout.water:
			for r in pool.rects:
				if level.rect(r).has_point(site.origin): submerged+=1
	check(dry_sources>0 and wet_sources>0,"Sources have both real dry and water-surface receivers")
	check(submerged==0,"No ambient droplet starts inside flooded tunnels")
	check(unanchored==0,"Origins remain attached to physical/painted ceilings or beam undersides")
	var w1: Dictionary=fx.receiver_below(Vector2(3650,3850))
	var w2: Dictionary=fx.receiver_below(Vector2(9060,2600))
	check(w1.get("wet",false) and is_equal_approx(float(w1.point.y),3968),"W1 free surface intercepts a drop before the submerged floor")
	check(w2.get("wet",false) and is_equal_approx(float(w2.point.y),2816),"W2 free surface intercepts a drop before the submerged floor")
	var slope: Dictionary=fx.receiver_below(Vector2(960,2350))
	check(not slope.get("wet",true) and is_equal_approx(float(slope.point.y),2502),"Entry ramp intercepts a drop before the lower rock bed")
	var near_floor: Dictionary=fx.receiver_below(Vector2(1600,2550))
	check(is_equal_approx(float(near_floor.point.y),2558),"A nearby landing is not skipped in favour of a lower storey")
	var gate_probe:=Vector2(5408,3696)
	var closed_gate: Dictionary=fx.receiver_below(gate_probe)
	level.open_doors.S1=true
	fx.refresh_receivers("S1")
	var opened_gate: Dictionary=fx.receiver_below(gate_probe)
	check(is_equal_approx(float(closed_gate.point.y),3712) and float(opened_gate.point.y)>3712,"An opened shortcut no longer catches drops on its vanished gate")
	level.open_doors.S1=false
	fx.refresh_receivers("S1")
	var hp: int=level.player.combat_stats.health
	await observe(12.0,"entry")
	check(fx.emitted_count>=2 and fx.emitted_count<=7,"Normal entry density stays sparse over twelve seconds: %d" % fx.emitted_count)
	check(fx.dry_hit_count>0,"Natural entry drops reach a dry surface and produce a small splash")
	level.set_process(false)
	level.camera.position=Vector2(9110,2990)
	level.camera.reset_smoothing()
	for i in 5: await process_frame
	var hits_before: int=fx.water_hit_count
	await observe(18.0,"water")
	check(fx.water_hit_count>hits_before,"Natural pool drops end in a small water ripple")
	level.camera.position=Vector2(5824,2458)
	level.camera.reset_smoothing()
	for i in 8: await process_frame
	var view: Rect2=fx._view.grow(96)
	var stale:=0
	for drop in fx.drops:
		if not view.has_point(drop.pos): stale+=1
	for hit in fx.impacts:
		if not view.has_point(hit.pos): stale+=1
	check(stale==0,"Moving the view clears old distant drops and impacts")
	check(fx.max_live_drops<=3 and fx.impacts.size()<=6,"Live droplets and impact feedback stay bounded")
	check(level.player.combat_stats.health==hp and level.oxygen.fraction()>0.99,"Ambient moisture leaves health, oxygen and gameplay water unchanged")
	var report={"checks":checks,"failures":failures,"sources":fx.sources.size(),"dry_sources":dry_sources,"wet_sources":wet_sources,
		"emitted":fx.emitted_count,"dry_hits":fx.dry_hit_count,"water_hits":fx.water_hit_count,"max_live":fx.max_live_drops,
		"observed_frames":frames,"captures":observations}
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	report.checks=checks
	report.failures=failures
	var file:=FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	finish("CAVERN AMBIENT DRIPS")


func observe(seconds: float,area: String) -> void:
	for i in int(seconds*60):
		await process_frame
		frames+=1
		if DisplayServer.get_name()=="headless": continue
		for drop in fx.drops:
			var phase: String="bead" if float(drop.bead)>0 else "fall"
			if phase=="fall" and (float(drop.speed)<400 or not fx._view.grow(-12).has_point(drop.pos)): continue
			await capture_once(area+"_"+phase)
		for hit in fx.impacts:
			if float(hit.age)<0.16: continue
			await capture_once(area+("_ripple" if hit.wet else "_splash"))


func capture_once(label: String) -> void:
	if captured.has(label): return
	captured[label]=true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	var positions: Array=[]
	for drop in fx.drops: positions.append([drop.pos.x,drop.pos.y])
	observations.append({"label":label,"drops":positions,"view":[fx._view.position.x,fx._view.position.y,fx._view.size.x,fx._view.size.y]})

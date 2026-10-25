extends "../../support/harness.gd"
## Check every emitted triangle for the complete swing and fading tail, not one screenshot.

func run() -> void:
	use_memory_progress()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.select_combo_library(8)
	dev.play_action(4)
	var formation := dev.adapter.master.get_node("FlyingSwordPreview") as MasterFlyingSwordFormation
	formation.self_stepping = false
	formation.advance(2.51)
	var barrage := formation.barrage
	var old_clipped := 0
	for event: Dictionary in barrage.timeline:
		if event.do != "slash": continue
		var ribbon := barrage._make_ribbon(event)
		barrage.add_child(ribbon)
		var old_half := (ceili((ribbon.radius*maxf(1,ribbon.squash)+32.0)/ribbon.pixel)+2)*ribbon.pixel
		var old_bounds := Rect2(-Vector2.ONE*old_half,Vector2.ONE*old_half*2)
		var fits := true
		var clipped_before := false
		for i in ceili((ribbon.duration+ribbon.tail)*240)+1:
			ribbon.advance(1.0/240.0)
			if ribbon.blade.mesh == null: continue
			var vertices: PackedVector3Array = ribbon.blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := Vector2(vertex.x,vertex.y)*ribbon.pixel
				fits = fits and ribbon.render_bounds.grow(-ribbon.pixel*2).has_point(point)
				clipped_before = clipped_before or not old_bounds.has_point(point)
		check(fits,"%s: every blade and echo vertex fits with padding through the whole swing and tail" % event.flight.name)
		check((ribbon.blade.position*ribbon.pixel+ribbon.render_bounds.position).is_zero_approx(),"%s: larger render canvas preserves the sword/trail world pivot" % event.flight.name)
		if clipped_before: old_clipped += 1
		ribbon.free()
	check(old_clipped > 0,"Reproduced the old radius-only canvas clipping on %d flight variants" % old_clipped)
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FLYING SWORD BOUNDS")

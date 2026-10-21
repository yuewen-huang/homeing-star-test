extends "../support/harness.gd"
## No legacy strip: the shared cue plays exactly one baked star + converging shards.
func run() -> void:
	use_memory_progress()
	var cue := DangerFlash.new(&"red")
	root.add_child(cue)
	check(not cue.visible, "A cue starts hidden")
	var chest := Vector2(400,300)
	for palette: StringName in [&"red", &"gold"]:
		cue.kind = palette
		check(cue.show_at(0.06,1.0,chest), "The %s cue plays during wind-up" % palette)
		check(cue.pieces.size() == 2 and cue.get_child_count() == 2, "Exactly one star and one shard convergence, without a sprite strip")
		check(cue.pieces[0].shape == &"star" and cue.pieces[0].burst_spikes == 4 and cue.pieces[1].spark_converge, "Production four-point star and inward shards")
		for piece in cue.pieces:
			check(not piece._clip.is_empty() and piece._display != null, "Both colours resolve existing production atlases")
			check(piece.palette_key == palette and is_equal_approx(piece.age,0.06), "Colour and action clock reach both pieces")
		var star = cue.pieces[0]
		cue.show_at(0.20,-1.0,chest,0.5)
		check(cue.position == chest and cue.scale == Vector2(-1,1) and is_equal_approx(cue.modulate.a,0.5), "Mirror and fade the entire cue around its chest anchor")
		cue.show_at(0.0,1.0,chest)
		check(cue.pieces[0] == star and cue.pieces[0].age == 0.0, "Replaying resets baked age without stacking effects")
		check(not cue.show_at(-0.1,1.0,chest) and not cue.visible, "Hidden before the cue")
		check(not cue.show_at(DangerFlash.DURATION,1.0,chest), "Hidden at the cue end")
		check(not cue.show_at(0.06,1.0,chest,0.0), "Hidden with an invisible body")
	check(DeerBossVFX.RED_WARNING_DURATION == DangerFlash.DURATION, "Deer uses the shared baked lifetime")
	cue.free()
	expect_save_untouched()
	finish("DANGER FLASH")

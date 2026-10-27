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
		check(cue.pieces.size() == 2 and cue.get_child_count() == 3 and cue.flare is ColorRect and cue.flare.material.shader == DangerFlash.FLARE_SHADER, "Baked star and shards plus the runtime flare")
		check(cue.pieces[0].shape == &"star" and cue.pieces[0].burst_spikes == 4 and cue.pieces[1].spark_converge, "Production four-point star and inward shards")
		for piece in cue.pieces:
			check(not piece._clip.is_empty() and piece._display != null, "Both colours resolve existing production atlases")
			check(piece.palette_key == palette, "Palette reaches both baked pieces")
		var build := (0.06 - DangerFlash.start_age()) / DangerFlash.PREWARN
		check(is_equal_approx(cue.pieces[0].age, .06 * build) and is_equal_approx(cue.pieces[1].age, .24 * build), "Both baked pieces follow the full build-up")
		var star = cue.pieces[0]
		cue.show_at(0.20,-1.0,chest,0.5)
		check(cue.position == chest and cue.scale == Vector2(-1,1) and is_equal_approx(cue.modulate.a,0.5), "Mirror and fade the entire cue around its chest anchor")
		cue.show_at(0.0,1.0,chest)
		check(cue.pieces[0] == star and is_equal_approx(cue.pieces[0].age, .06 * (-DangerFlash.start_age()) / DangerFlash.PREWARN), "Replaying resamples baked age without stacking effects")
		check(cue.show_at(-0.1,1.0,chest), "Full cue is visible at negative age")
		check(not cue.show_at(DangerFlash.start_age() - .001,1.0,chest), "Hidden before full cue")
		check(cue.show_at(DangerFlash.start_age(),1.0,chest), "Visible at full cue start")
		cue.beat = true
		check(not cue.show_at(DangerFlash.start_age(true) - .001,1.0,chest), "Hidden before short beat")
		check(cue.show_at(DangerFlash.start_age(true),1.0,chest) and not cue.pieces[1].visible, "Short beat starts without gathering shards")
		cue.beat = false
		check(not cue.show_at(DangerFlash.DURATION,1.0,chest), "Hidden at the cue end")
		check(not cue.show_at(0.06,1.0,chest,0.0), "Hidden with an invisible body")
	check(is_equal_approx(DangerFlash.start_age(), -.32) and is_equal_approx(DangerFlash.start_age(true), .14), "Full and short modes start at the intended ages")
	check(is_equal_approx(DangerFlash.WARNING_LEAD - DangerFlash.PEAK_TIME, .10) and is_equal_approx(DangerFlash.DURATION, .36), "Peak precedes release by 100 ms and cue ends at 360 ms")
	for beat in [false, true]:
		cue.beat = beat
		var previous := -1.0
		for index in 11:
			var age := lerpf(DangerFlash.start_age(beat), DangerFlash.PEAK_TIME, index / 10.0)
			cue.show_at(age,1.0,chest)
			check(cue.pieces[0].modulate.a >= previous, "Star brightness rises toward the peak")
			previous = cue.pieces[0].modulate.a
		check(DangerFlash.frame_at(DangerFlash.DURATION,beat) == -1, "Each mode is hidden at the end")
	check(DeerBossVFX.RED_WARNING_DURATION == DangerFlash.DURATION, "Deer uses the shared baked lifetime")
	cue.free()
	expect_save_untouched()
	finish("DANGER FLASH")

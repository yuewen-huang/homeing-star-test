extends "../support/harness.gd"
## DangerFlash (restructure P4, 2026-10-19): the red / gold chest glint the deer and the master
## share. Must reproduce, frame by frame, what each drew by hand: the 5-frame curve, art,
## size, mirroring around the glint's visual middle, opacity, and hiding outside the cue.

func run() -> void:
	use_memory_progress()
	var red := DangerFlash.new(&"red")
	var gold := DangerFlash.new(&"gold")
	check(red.hframes == 5 and not red.visible and red.texture.resource_path.ends_with("red_counter_warning_625x87_5f.png"), "A red flash starts hidden on the red glint strip")
	check(gold.texture.resource_path.ends_with("gold_unparryable_warning_625x87_5f.png") and gold.scale.is_equal_approx(Vector2.ONE * 1.2), "A gold flash uses the gold strip at 1.2")
	check(DeerBossVFX.FLASH_FRAMES == DangerFlash.FRAMES and DeerBossVFX.RED_WARNING_TEXTURE == DangerFlash.RED_TEXTURE, "The deer's old constant names point at the shared flash")
	var expected_frames: Array[int] = []
	var frames: Array[int] = []
	for age: float in [0.0, 0.049, 0.05, 0.12, 0.19, 0.25, 0.31, 0.5]:
		expected_frames.append(DeerBossVFX.flash_frame(age))
		frames.append(DangerFlash.frame_at(age))
	check(frames == [0, 0, 1, 2, 3, 4, -1, -1] and frames == expected_frames, "The curve plays 5 frames over 0.31 s (%s)" % str(frames))

	var chest := Vector2(400, 300)
	check(red.show_at(0.06, 1.0, chest), "It shows during the cue")
	var curve: Array = DangerFlash.FRAMES[1]
	check(red.frame == 1 and not red.flip_h and red.offset == Vector2(-17, -2) and red.position == chest, "Facing right: frame, centre offset and anchor")
	check(red.scale.is_equal_approx(Vector2.ONE * 1.3 * float(curve[1])) and is_equal_approx(red.modulate.a, float(curve[2])), "Size and opacity follow the curve")
	red.show_at(0.06, -1.0, chest, 0.5)
	check(red.flip_h and red.offset == Vector2(17, -2) and is_equal_approx(red.modulate.a, 0.5 * float(curve[2])), "Facing left it mirrors around its visual middle and fades with the body")
	check(not red.show_at(-0.2, 1.0, chest) and not red.visible, "Hidden before its cue")
	check(not red.show_at(0.4, 1.0, chest) and not red.visible, "Hidden after its cue")
	check(not red.show_at(0.06, 1.0, chest, 0.0) and not red.visible, "Hidden while the body is invisible")
	gold.show_at(0.0, 1.0, chest)
	check(gold.offset == Vector2(37, 0), "The gold glint has its own visual middle")
	red.kind = &"gold"
	check(red.texture == DangerFlash.GOLD_TEXTURE, "Changing the kind swaps the art")
	red.free()
	gold.free()
	expect_save_untouched()
	finish("DANGER FLASH")

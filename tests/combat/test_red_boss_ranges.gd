extends "../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var owner_node := Node2D.new()
	root.add_child(owner_node)
	var warning := AttackTelegraph.create_for(owner_node)
	for danger in 3:
		warning.begin()
		warning.rectangle(Rect2(10,20,180,70),danger,.2)
		warning.oval(Vector2(400,300),Vector2(90,40),danger,.8)
		warning.strip(Vector2(10,10),Vector2(120,100),30,danger,.6)
		warning.end()
		for mark in warning._marks:
			check(mark.material.get_shader_parameter("warning_color") == AttackTelegraph.RANGE_RED, "Danger %d uses red range independent of parry type" % danger)
		var before := warning._marks[0].transform
		warning.begin()
		warning.rectangle(Rect2(10,20,180,70),danger,.9)
		warning.end()
		check(before.is_equal_approx(warning._marks[0].transform), "Countdown preserves the committed footprint")
	var panda = load("res://scenes/bosses/panda/panda_boss.tscn").instantiate()
	var panda_warning := AttackTelegraph.create_for(panda)
	check(panda_warning.panda_palette and panda_warning.range_color(2) == AttackTelegraph.COLORS[2], "Actual panda ancestor retains its exception")
	panda.free()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	warning.begin()
	warning.rectangle(Rect2(10,20,180,70),0,.2)
	warning.end()
	check(warning._used == 0 and not warning._marks[0].visible, "Nightmare still suppresses area assistance")
	owner_node.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("RED BOSS RANGES")

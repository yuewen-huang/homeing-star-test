extends "../../support/harness.gd"

func step(formation: MasterFlyingSwordFormation, seconds: float) -> void:
	for i in ceili(seconds*240): formation.advance(1.0/240.0)

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
	step(formation,2.51)
	var barrage := formation.barrage
	check(barrage != null and barrage.sword.state == MasterFlyingSword.State.BARRAGE, "Rage preview detaches the existing blue greatsword")
	check(formation.swords.size() == 1, "Rage immediately clears the other patrol swords")
	check(not formation.request_sweep(Vector2.ZERO) and not formation.rage(Vector2.ZERO), "Nine-cut action owns its sword exclusively")
	var slashes: Array = barrage.timeline.filter(func(e: Dictionary) -> bool: return e.do == "slash")
	var times: Array = [0.45,0.9,1.3,1.48,1.64,1.96,2.43,2.68,3.18]
	check(slashes.size() == 9, "Existing rift_dancer choreography contains exactly nine cuts")
	for i in 9:
		check(is_equal_approx(float(slashes[i].t),times[i]) and slashes[i].palette == ("gold" if i == 8 else "normal"), "Authored cut %d retains its timing and requested blue/gold palette" % (i+1))
	var checked: Dictionary = {}
	var checked_pause := false
	var checked_vanish := false
	for i in 1800:
		var previous_cut := barrage.slash_count
		var previous_pose := barrage.sword.global_transform
		formation.advance(1.0/240.0)
		if barrage.slash_count > previous_cut and previous_cut > 0:
			check(previous_pose.origin.distance_to(barrage.sword.global_position) < 10 and absf(wrapf(previous_pose.get_rotation()-barrage.sword.global_rotation,-PI,PI)) < 0.2, "Cut %d releases from its prepared pose without snapping" % barrage.slash_count)
		if not checked_vanish and barrage.slash_count == 9 and is_instance_valid(barrage.active) and barrage.active.age >= barrage.active.duration:
			check(not barrage.sword.visible, "Gold weapon disappears at the end of its swing while the ribbon fades")
			checked_vanish = true
		if is_instance_valid(barrage.active) and not barrage.active.is_queued_for_deletion():
			var ribbon := barrage.active
			if ribbon.age > 0 and ribbon.age < ribbon.duration and not checked.has(barrage.slash_count):
				var pose := ribbon.blade_pose(ribbon.age)
				check((ribbon.blade_pose(0).hilt as Vector2).distance_to(ribbon.blade_pose(ribbon.duration).hilt) > 100,"Cut %d moves the sword guard along its flight variant instead of pivoting in place" % barrage.slash_count)
				check(barrage.sword.to_global(Vector2(-17,0)).distance_to(ribbon.to_global(pose.hilt)) < 0.01 and barrage.sword.to_global(Vector2(120,0)).distance_to(ribbon.to_global(pose.tip)) < 0.01, "Cut %d sword guard and tip stay attached to the rendered ribbon" % barrage.slash_count)
				var expected := Color("ffffed") if barrage.slash_count == 9 else Color("f5ffff")
				check(ribbon.palette[0] == expected and ribbon.shader_material.get_shader_parameter("ink_0") == expected, "Cut %d applies its palette to the actual shader" % barrage.slash_count)
				check(float(barrage.sword.energy.get_shader_parameter("gold")) == (1.0 if barrage.slash_count == 9 else 0.0), "Weapon turns gold only for the ninth cut")
				checked[barrage.slash_count] = true
		if not checked_pause and barrage.pause_remaining > 0.04:
			var before := barrage.sword.global_transform
			var age := barrage.active.age
			var clock := barrage.elapsed
			step(formation,0.025)
			check(barrage.sword.global_transform.is_equal_approx(before) and is_equal_approx(barrage.elapsed,clock) and is_equal_approx(barrage.active.age,age), "Authored impact pause freezes both sword and ribbon together")
			checked_pause = true
		if barrage.finished: break
	check(checked.size() == 9 and barrage.slash_count == 9 and barrage.contact_count == 9 and checked_pause and checked_vanish, "All nine cuts and the gold finish execute once, then the weapon vanishes")
	step(formation,1)
	check(barrage.finished and formation.swords.is_empty() and barrage.sword.is_queued_for_deletion(), "After the gold cut no weapon returns to patrol")
	step(formation,3)
	check(barrage.slash_count == 9 and dev.player.combat_stats.health == dev.player.combat_stats.max_health, "Rage preview does not repeat or apply demo damage")
	dev.play_action(4)
	formation = dev.adapter.master.get_node("FlyingSwordPreview")
	formation.self_stepping = false
	step(formation,3)
	dev.reset_room()
	await process_frame
	check(dev.specimen.find_children("FlyingSwordPreview","",true,false).is_empty(), "Reset during barrage clears the sword and all ribbons")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FLYING SWORD BARRAGE")

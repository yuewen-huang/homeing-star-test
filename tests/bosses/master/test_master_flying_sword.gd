extends "../../support/harness.gd"
var starts := 0
var finishes := 0

func step(formation: MasterFlyingSwordFormation, seconds: float) -> void:
	for i in ceili(seconds * 120): formation.advance(1.0 / 120.0)

func run() -> void:
	use_memory_progress()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.select_combo_library(6)
	dev.play_action(4)
	var formation := dev.adapter.master.get_node("FlyingSwordPreview") as MasterFlyingSwordFormation
	formation.self_stepping = false
	check(formation.swords.size() == 3, "Three procedural pale-blue energy swords populate the orbit")
	check(formation.to_local(formation.orbit_position(0)).is_equal_approx(Vector2(460,0)), "Horizontal orbit radius is doubled to 460 local pixels")
	var quarter_slot := formation.to_local(formation.orbit_position(1))
	check(is_equal_approx(absf(quarter_slot.y),sin(TAU/3.0)*160), "Vertical orbit radius is doubled to 160 local pixels")
	for sword in formation.swords:
		sword.slash_started.connect(func() -> void: starts += 1)
		sword.slash_finished.connect(func() -> void: finishes += 1)
		check(sword.get_children().filter(func(n: Node) -> bool: return n is Polygon2D).size() == 7 and sword.energy.shader != null, "Sword silhouette and energy shader are generated without raster art")
	var before := formation.swords[0].global_position
	step(formation,1.0)
	check(before.distance_to(formation.swords[0].global_position) > 40, "Sword visibly follows its elliptical orbit")
	formation.advance(0)
	var clock := formation.clock
	check(is_equal_approx(clock,1.0), "Zero action time freezes the formation")
	step(formation,1.55)
	var active: MasterFlyingSword
	for sword in formation.swords:
		if sword.state == MasterFlyingSword.State.WARNING: active = sword
	check(active != null and active.telegraph.visible, "One sword detaches and warns before sweeping")
	check(not formation.request_sweep(Vector2.ZERO), "A second sword cannot attack during the warning")
	var locked := active._locked
	formation.target.position.x += 300
	step(formation,0.3)
	check(active._locked == locked, "Moving the target after warning cannot curve the committed slash")
	while active.state == MasterFlyingSword.State.WARNING and active.state_age < 0.53:
		formation.advance(1.0/120.0)
	var held_pose := active.global_transform
	step(formation,0.06)
	check(active.state == MasterFlyingSword.State.WARNING and active.global_transform.is_equal_approx(held_pose), "Greatsword pauses in its windup before releasing")
	for i in 120:
		if active.state == MasterFlyingSword.State.FINISH_HOLD: break
		formation.advance(1.0/120.0)
	held_pose = active.global_transform
	step(formation,0.08)
	check(active.state == MasterFlyingSword.State.FINISH_HOLD and active.global_transform.is_equal_approx(held_pose), "Greatsword briefly holds its follow-through")
	check(not formation.request_sweep(Vector2.ZERO), "Follow-through hold still prevents a second attack")
	step(formation,2.0)
	check(starts == 1 and finishes == 1, "Preview performs exactly one sweep")
	check(formation.swords.all(func(s: MasterFlyingSword) -> bool: return s.state == MasterFlyingSword.State.ORBIT), "Sweeping sword smoothly returns to the rotating formation")
	step(formation,8.0)
	check(starts == 1, "No pursuit or repeated attack follows the one-cut preview")
	check(dev.player.combat_stats.health == dev.player.combat_stats.max_health and formation.find_children("*","Area2D",true,false).is_empty(), "Motion preview creates no damage or hidden collision")
	dev.select_combo_library(7)
	dev.play_action(4)
	formation = dev.adapter.master.get_node("FlyingSwordPreview")
	formation.self_stepping = false
	step(formation,3.5)
	active = null
	for sword in formation.swords:
		if sword.state == MasterFlyingSword.State.DEFLECTED: active = sword
	check(active != null and not active.telegraph.visible, "Deflection callback interrupts the slash and opens a gap")
	step(formation,1.5)
	check(active.state == MasterFlyingSword.State.DEFLECTED, "Deflected sword remains suspended for the intended opening")
	step(formation,2.0)
	check(active.state == MasterFlyingSword.State.ORBIT, "After the suspension the sword rejoins its orbit")
	dev.adapter.master.phase = 2
	formation.self_stepping = true
	formation._process(0.01)
	check(formation.is_queued_for_deletion(), "Leaving phase one clears the visual formation")
	dev.reset_room()
	await process_frame
	check(dev.specimen.get_child_count() == 2 and dev.specimen.find_children("FlyingSwordPreview","",true,false).is_empty(), "Reset removes the swords, trails and warning lines")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FLYING SWORD")

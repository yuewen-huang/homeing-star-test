extends "../../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.play_action(4)
	var master: MasterBoss = room.adapter.master
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	var rhythm = master.clash_rhythm
	# The dummy must stand at the authored landing, rather than expecting the dive
	# to chase the old preview target. Use the same blade-ground anchor as the AOE.
	room.dummy.position.x = rhythm.accents.global_position.x+rhythm.accents.landing_offset.x
	room.adapter.set_preview_target(room.dummy.position)
	check(rhythm.id == &"air_qi_combo" and MasterClashRhythm.ORDER.has(rhythm.id), "Air-qi sample is part of the production move table")
	check(rhythm.strikes.size() == 1 and is_equal_approx(float(rhythm.strikes[0].t),2.14), "Only the fast landing adds a melee hit; the opening flick deals no damage")
	var peak := 0.0
	var airborne_releases := true
	var freeze_checked := false
	var stable := true
	var previous_releases := 0
	var push_before: Vector2 = room.player.global_position
	room.player.global_position = master.global_position+Vector2(rhythm.direction*100.0,0)
	push_before = room.player.global_position
	master.combat_target = room.player
	var pushed := false
	for i in 430:
		master._process(1.0/120.0)
		room._process(0.0)
		peak = maxf(peak,555.0-master.position.y)
		stable = stable and is_zero_approx(master.animated_sprite.rotation)
		if not pushed and rhythm.elapsed >= 0.58:
			check((room.player.global_position.x-push_before.x)*rhythm.direction > 80.0, "Opening sword flick pushes the real Lan through the shared shove contract")
			# Keep the observer out of the longer flight path while testing dummy hits.
			room.player.global_position = Vector2(70,555)
			master.combat_target = room.adapter.target
			pushed = true
		if rhythm.releases > previous_releases:
			airborne_releases = airborne_releases and master.position.y < 555.0
			previous_releases = rhythm.releases
		if not freeze_checked and rhythm.releases == 1:
			var qi = rhythm.projectiles[-1]
			var before: Vector2 = qi.global_position
			var time: float = rhythm.elapsed
			master.start_parry_feedback()
			master._process(0.01)
			check(rhythm.elapsed == time and qi.global_position == before, "Real parry pause freezes the jump and flying qi on one action clock")
			master.parry_pause_remaining = 0.0
			freeze_checked = true
		await process_frame
	check(rhythm.releases == 3 and airborne_releases, "Exactly three qi releases occur in the air")
	check(peak > 230.0 and stable and is_equal_approx(master.position.y,555.0), "Full-height jump lands at the original floor without sprite rotation")
	check(rhythm.finished and master.clash_rhythm == null, "Landing study finishes and restores recovery")
	check(room.dummy.contacts.size() == 4, "Dummy receives three reserved qi contacts and exactly one landing hit: %s" % [room.dummy.contacts])
	room.play_action(4)
	master = room.adapter.master
	master.set_process(false)
	master._process(0.90)
	master._interrupt_for_special(0.0)
	check(is_equal_approx(master.position.y,555.0), "Interrupting the jump restores the floor and clears the action")
	room.reset_room()
	await process_frame
	check(room.specimen.get_child_count() == 2, "Reset clears airborne study and projectiles")
	for facing in [-1.0,1.0]:
		for tick in [1.0/120.0,1.0/30.0]:
			_check_fixed_dive(room,facing,tick)
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER AIR QI STUDY")

func _check_fixed_dive(room: Node, facing: float, tick: float) -> void:
	room.adapter._rebuild()
	var master: MasterBoss = room.adapter.master
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	master.position.x = 700.0 if facing < 0.0 else 400.0
	var start_x := master.position.x
	room.player.global_position = master.global_position+Vector2(facing*100.0,0)
	master.combat_target = room.player
	master.start_clash_rhythm(&"air_qi_combo")
	var rhythm = master.clash_rhythm
	var last_x := 0.0
	var sampled := 0
	var moved := false
	var push_ok := true
	while rhythm.elapsed < 2.30:
		master._process(tick)
		for qi in rhythm.projectiles:
			if is_instance_valid(qi): qi.hitbox.set_physics_process(false)
		if sampled == 0 and rhythm.elapsed >= 1.0:
			last_x = room.player.global_position.x
			sampled = 1
		if sampled >= 1 and sampled <= 3 and rhythm.elapsed >= [1.30,1.64,1.98][sampled-1]:
			push_ok = push_ok and absf((room.player.global_position.x-last_x)*facing-65.0) < 0.05
			last_x = room.player.global_position.x
			sampled += 1
		if not moved and rhythm.elapsed >= 2.0:
			# Cross behind the caster before the dive: neither facing nor landing tracks.
			room.player.global_position.x = start_x-facing*120.0
			moved = true
	check(push_ok and sampled == 4,"Three release pulses each shove Lan 65px: facing %s, tick %s" % [facing,tick])
	check(is_equal_approx(master.position.x,start_x+facing*340.0) and rhythm.direction == facing,
		"Dive stays on its fixed mirrored path after Lan crosses behind: facing %s, tick %s" % [facing,tick])

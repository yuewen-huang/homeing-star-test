extends "../../support/harness.gd"
## Production-only regression: exact release, measured mirroring, fading and cleanup.

func run() -> void:
	use_memory_progress()
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	for id: StringName in [&"inertia_combo", &"lunge_combo", &"air_qi_combo"]:
		for facing in [-1.0, 1.0]:
			room.adapter._rebuild()
			var boss: MasterBoss = room.adapter.master
			boss.position = Vector2(640, 555)
			room.adapter.target.position.x = 640 + facing * 180
			boss.set_process(false)
			boss.attack_hitbox.set_physics_process(false)
			boss.start_clash_rhythm(id)
			var r := boss.clash_rhythm as MasterAnnotatedCombo
			check(r != null, "%s uses the reviewed annotated runner" % id)
			var gaps := true
			var geometry := true
			var fading := true
			var mirrored := true
			for i in r.cuts.size():
				var cut: Dictionary = r.cuts[i]
				if i > 0: gaps = gaps and float(cut.contact_at) - float(r.cuts[i-1].contact_at) >= 0.35 - 0.0001
				r.elapsed = float(cut.release)
				r.step(r.elapsed)
				var ribbon: MasterTrajectoryRibbon = r._contact_ribbons[i].node
				geometry = geometry and boss.attack_collision_shape.shape is ConvexPolygonShape2D
				var point: Vector2 = ribbon.blade_pose(0.0).hilt
				mirrored = mirrored and point.is_equal_approx(Vector2(cut.poses[0].hilt[0] * facing, cut.poses[0].hilt[1]))
				geometry = geometry and ribbon.look == &"trail" and ribbon.crescent_profile(ribbon.age, 0.0) == 1.0
				if String(cut.base) == "dash":
					geometry = geometry and int(cut.turn) == -1 and not ribbon.thrust and ribbon.reference_blade_length > 0.0 and ribbon.width > 50.0
				r.elapsed = float(cut.end) + 0.06
				r.step(r.elapsed)
				fading = fading and boss.attack_hitbox.attack == null and ribbon.visible and not ribbon.is_done() and ribbon.blade.mesh != null
				ribbon.advance(ribbon.duration + ribbon.tail - ribbon.age + 0.001)
				fading = fading and ribbon.is_done()
			check(gaps, "%s %s keeps manual-parry contact spacing" % [id, facing])
			check(geometry and mirrored, "%s %s retains blunt rifts, broad returning dash and mirrored measured geometry at exact release" % [id, facing])
			check(fading, "%s %s retains visible tails after damage closes and finishes at the new lifetime" % [id, facing])
			r.cancel()
			check(r.ghosts.is_empty(), "Interrupt removes specimen recovery silhouettes")
	room.reset_room()
	await process_frame
	check(room.specimen.get_child_count() == 2, "Reset removes every old specimen effect")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("MASTER ANNOTATED COMBOS")

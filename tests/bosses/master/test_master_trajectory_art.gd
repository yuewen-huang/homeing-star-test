extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var master: MasterBoss
var profiles: Dictionary = {}

func tick_to(time: float) -> void:
	var guard := 0
	while master.clash_rhythm != null and master.clash_rhythm.elapsed + 0.00001 < time and guard < 3000:
		master._process(minf(1.0 / 120.0, time - master.clash_rhythm.elapsed))
		guard += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	for id: StringName in [&"press_return", &"blink_return", &"spin_delayed", &"air_plunge"]:
		room.adapter._rebuild()
		master = room.adapter.master
		master.set_process(false)
		master.attack_hitbox.set_physics_process(false)
		master.start_clash_rhythm(id)
		var r := master.clash_rhythm
		for i in r.strikes.size():
			var strike := r.strikes[i]
			var lead := r.smear_lead(strike)
			tick_to(float(strike.t) - lead - 0.01)
			if i == 0: await capture(String(id) + "_warning")
			tick_to(float(strike.t) + 0.025)
			var trail: MasterTrajectoryRibbon = r.winds.back().node
			check(trail.profile_name != &"" and trail.pose_keys.size() >= 3, "Actual source-frame trajectory supplied")
			profiles[trail.profile_name] = true
			if trail.profile_name == &"return":
				check(trail.pose_keys.all(func(p: Dictionary) -> bool: return (p.tip as Vector2).y < -15.0), "Waist return sweep stays above the ground without clipping its geometry")
			for pose: Dictionary in trail.pose_keys:
				var sample := trail.blade_pose(float(pose.u) * trail.duration)
				check((sample.tip as Vector2).distance_to(sample.hilt) > (pose.tip as Vector2).distance_to(pose.hilt), "Wind extends past the measured weapon tip")
			check(not trail.samples.is_empty() and trail.blade.mesh != null, "Retained geometry is rendered")
			room._process(0)
			await capture(String(id) + "_cut_%d_" % i + String(trail.profile_name))
			if id == &"spin_delayed" and i == 0:
				var frozen := trail.age
				master.start_parry_feedback()
				master._process(0.01)
				check(is_equal_approx(trail.age, frozen), "New trajectories freeze with parry feedback")
			tick_to(float(strike.close) + 0.01)
		tick_to(r.duration - 0.01)
		await capture(String(id) + "_recovery")
		master._interrupt_for_special(0)
		for i in 100: master._process(1.0 / 60.0)
		await process_frame
		check(master.fading_winds.is_empty(), "Interrupted source trajectories clean up")
	check(profiles.size() == 10, "Ten distinct motion profiles cover all new attacks")
	# Independent reverse-facing take catches accidental double mirroring.
	room.adapter.set_preview_target(Vector2(1000,555))
	room.adapter._rebuild()
	master = room.adapter.master
	master.set_process(false)
	master.start_clash_rhythm(&"spin_delayed")
	tick_to(1.025)
	await capture("heavy_facing_right")
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER SOURCE TRAJECTORY ART")

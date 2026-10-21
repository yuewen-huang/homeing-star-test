extends "../../support/harness.gd"

const Timing := preload("res://scripts/bosses/master/master_action_timing.gd")
var output := ""
var capture_frames := false

func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	capture_frames = OS.get_cmdline_user_args().has("capture") and DisplayServer.get_name() != "headless"
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	room.get_node("Camera2D").position = Vector2(640,260)
	room.get_node("Camera2D").zoom = Vector2.ONE*0.80
	for id: StringName in MasterClashRhythm.ORDER:
		var rows: Array = Timing.MAPS[id]
		var end := float(rows[-1][1])
		var monotone := true
		var reversible := true
		var positive_speed := true
		var previous := 0.0
		for i in 1001:
			var real_time := end*float(i)/1000.0
			var source := Timing.source_at(id,real_time)
			monotone = monotone and source+0.000001 >= previous
			reversible = reversible and absf(Timing.played_at(id,source)-real_time) < 0.000002
			if i > 0: positive_speed = positive_speed and source-previous > 0.00001
			previous = source
		check(monotone and reversible and positive_speed,"%s has a reversible forward-moving clock with no inserted freezes" % id)
		room.adapter._rebuild()
		var master: MasterBoss = room.adapter.master
		master.set_process(false)
		master.attack_hitbox.set_physics_process(false)
		master.position.x = 680
		room.adapter.target.position.x = 420
		master.start_clash_rhythm(id)
		var rhythm := master.clash_rhythm
		var beat_times: Array = []
		var next_beat := 0
		var frames := 0
		var played := 0.0
		var frozen_checked := false
		var source_clock_ok := true
		var wind_clock_ok := true
		while not rhythm.finished and frames < 600:
			master._process(1.0/120.0)
			played += 1.0/120.0
			if rhythm.finished: break
			source_clock_ok = source_clock_ok and absf(rhythm.elapsed-Timing.source_at(id,played)) < 0.0001
			while next_beat < rhythm.strikes.size() and rhythm.strikes[next_beat].done:
				beat_times.append(played)
				check(absf(played-Timing.played_at(id,float(rhythm.strikes[next_beat].t))) < 1.0/120.0+0.0001,"%s contact %d lands on the retimed source beat" % [id,next_beat+1])
				next_beat += 1
			for wind: Dictionary in rhythm.winds:
				if is_instance_valid(wind.node):
					wind_clock_ok = wind_clock_ok and absf(float(wind.node.age)-(rhythm.elapsed-float(wind.start))) < 0.0001
			if not frozen_checked and played > 0.4:
				var source := rhythm.elapsed
				var position := master.position
				master.start_parry_feedback()
				master._process(0.01)
				check(is_equal_approx(source,rhythm.elapsed) and master.position == position,"%s parry hit-stop still freezes mapped body and motion" % id)
				master.parry_pause_remaining = 0.0
				frozen_checked = true
			frames += 1
			if capture_frames and frames%6 == 0:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("%s_%03d.png" % [id,frames/6]))
		check(source_clock_ok and wind_clock_ok,"%s body and all static VFX use the same retimed source age" % id)
		check(next_beat == rhythm.strikes.size() and rhythm.finished,"%s keeps all authored contacts and completes recovery" % id)
		print("TIMING ",id," hits=",beat_times," recovery_end=",played)
		# The cue counts played seconds rather than the now non-uniform source seconds.
		room.adapter._rebuild()
		master = room.adapter.master
		master.set_process(false)
		master.start_clash_rhythm(id)
		rhythm = master.clash_rhythm
		var expected := Timing.played_at(id,float(rhythm.strikes[0].t))
		check(absf(rhythm.next_parry_contact_in()-expected) < 0.00001,"%s next-contact cue reports real remaining action seconds" % id)
		Engine.set_meta(&"master_vfx_baking",true)
		rhythm.advance(0.1)
		Engine.remove_meta(&"master_vfx_baking")
		check(absf(rhythm.elapsed-0.1) < 0.00001,"%s offline baking retains the original source timeline" % id)
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER ACTION TIMING")

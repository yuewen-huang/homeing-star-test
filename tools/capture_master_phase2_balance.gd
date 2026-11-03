extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(1)
	room.select_combo(1)
	var boss: MasterBoss = room.adapter.master
	boss.set_process(false)
	boss.charged_power = 1
	boss.phase_2_buff_remaining = 8
	boss._start_phase_2_finale(100)
	var action := boss.phase_2_body_action
	var at := 0.0
	var output := "D:/HomingStar/homeing-star-test/artifacts/master-phase2-balance"
	DirAccess.make_dir_recursive_absolute(output)
	for i in action.data.clips.size():
		var clip: Dictionary = action.data.clips[i]
		var sample := at + float(clip.groups[0].members[0].release) - float(clip.start_time) + .05
		action.advance(sample - action.elapsed)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%d.png" % i))
		at += float(clip.duration)
	check(action._danger_groups[0].danger == CombatAttackData.DangerType.COUNTERABLE_DANGER, "First finale warning is red, not gold")
	for event: Dictionary in action.vfx.definition.events:
		if event.do != "slash": continue
		print("CLAW time=", event.t, " palette=", event.palette)
	boss.finish_phase_2_body_action()
	check(is_equal_approx(boss.phase_2_idle_remaining, 1.9), "Sobered finale leaves a real 1.9 second recovery")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER PHASE TWO BALANCE CAPTURE")

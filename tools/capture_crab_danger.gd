extends "../tests/support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	room.select_boss(8)
	room.set_playback_speed(2)
	var crab: CrystalCrabBoss = room.adapter.crab
	crab.set_physics_process(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	var output := "D:/HomingStar/homeing-star-test/artifacts/crab-danger"
	DirAccess.make_dir_recursive_absolute(output)
	for id in [&"heavy", &"gold", &"aftershock"]:
		crab.start_quake(id, Vector2(900,555))
		var release: float = crab.quake_beats[-1].t
		var glint := crab.quake_vfx.glint
		for stage in 3:
			var sample: float = release + [-.55, -.10, .12][stage]
			while crab.quake_time < sample - .000001:
				crab._physics_process(minf(1.0/120, sample-crab.quake_time))
			if stage == 0: check(glint.visible, "Nightmare retains the full danger buildup: " + String(id))
			if stage == 1:
				check(glint.visible and crab.quake_vfx.warning._suppressed, "Danger remains readable with all floor ranges hidden: " + String(id))
				check(absf(float(glint.flare.material.get_shader_parameter("t"))) < .001, "Shared flash peaks one tenth before contact: " + String(id))
				check(glint.kind == (&"red" if id == &"heavy" else &"gold"), "Flash color matches actual attack danger: " + String(id))
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(String(id)+".png"))
			if stage == 2: check(not glint.visible, "Flash clears after its strike: " + String(id))
	crab.start_quake(&"flurry", Vector2(900,555))
	crab._physics_process(.5)
	check(not crab.quake_vfx.glint.visible, "Normal drumming never displays a red or gold cue")
	crab.start_quake(&"heavy", Vector2(900,555))
	crab._physics_process(.8)
	crab.start_idle()
	check(not crab.quake_vfx.glint.visible, "Cancellation clears the danger cue")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("CRAB SHARED DANGER CAPTURE")

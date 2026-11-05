extends "../../support/harness.gd"
## Native captures use the real manual development-room action executor.
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_vine_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	room.player.show()
	room.dummy.hide()
	var deer: Node2D = room.adapter.boss
	deer.set_physics_process(false)
	deer.manual_control = true
	var movie := OS.get_cmdline_user_args().has("--capture-animation")
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var feedback := root.get_node("CombatFeedback")
	feedback.set_process(false)
	for kind in [1,2]:
		deer.restart_duel()
		# restart_duel enables physics again; the capture owns every action tick.
		deer.set_physics_process(false)
		deer.vfx.set_process(false)
		deer.position = Vector2(350,555)
		room.player.position = Vector2(688,555)
		deer.preview_aim = room.player.position
		deer.start_phrase(kind)
		var visible_contact := false
		var clock_stable := true
		for frame in 450:
			deer._physics_process(1.0/60)
			deer.vfx._process(1.0/60)
			feedback._process(1.0/60)
			root.get_camera_2d().force_update_scroll()
			visible_contact = visible_contact or not deer.arena.probes().is_empty()
			if DisplayServer.get_name()!="headless" and ((movie and frame%3==0) or frame in [14,27,34,58,82,105,126,134,170,210,230,256,280,300,330,380]):
				var action_time: float = deer.arena.clock
				await process_frame
				clock_stable = clock_stable and is_equal_approx(action_time,deer.arena.clock)
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(output.path_join("thorn_%d_%03d.png" % [kind,frame]))
		check(visible_contact,"Stylized phrase %d retains real contact fronts" % kind)
		check(clock_stable,"Rendering never advances the manually sampled action clock")
		check(deer.arena.kind==0,"Stylized phrase %d clears its scene at recovery" % kind)
		check(room.player.combat_stats.health==100,"Visual capture remains safe/manual")
	# A real eruption has its own warning, independent of the body landing hit.
	deer.arena.begin(1)
	deer.arena.burst(640,true)
	deer.arena.advance(.45)
	check(deer.arena.probes().is_empty(),"Ground eruption has a safe readable warning")
	deer.arena.advance(.10)
	check(not deer.arena.probes().is_empty(),"Visible erupted thorns have actual contacts")
	deer.arena.clear()
	feedback.set_process(true)
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER STYLIZED VINE")

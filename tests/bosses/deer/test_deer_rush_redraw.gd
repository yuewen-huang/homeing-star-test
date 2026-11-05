extends "../../support/harness.gd"
## Old entry now verifies the authored replacement, not the rejected AI atlas.

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene = room
	await wait_frames(2)
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	var deer := room.adapter.boss as DeerDuelBoss
	room.set_physics_process(false)
	deer.set_physics_process(false)
	room.player.set_physics_process(false)
	room.player.position = Vector2(900,555)
	var art := deer.authored_body
	check(not deer.animated_sprite.has_node("RushRedraw"),"Rejected AI body is not instantiated")
	for facing in [-1.0,1.0]:
		deer.position = Vector2(600,555)
		deer.direction = facing
		for sample in [[&"idle_ING",.4],[&"bind_push_START",.8],[&"bind_push_ING",.6],[&"thrust_END",.7],[&"leap_turn_ING",.6],[&"flick_sweep_ING",.6],[&"roar_ING",.3],[&"hurt_END",.5],[&"walk_ING",.5],[&"heavy_START",.8],[&"heavy_ING",.1],[&"heavy_END",.6],[&"death_START",.8],[&"death_ING",.4],[&"death_END",.6]]:
			deer._sample_pose(sample[0],sample[1],1.0)
			check(art.visible and deer.animated_sprite.self_modulate.a == 0,"Authored pose replaces %s facing %d" % [sample[0],facing])
			var foot_local := (art.root_pixel-Vector2(128,128))*Vector2(facing,1)
			check(art.to_global(foot_local).distance_to(deer.global_position)<.01,"Measured root remains at boss origin without double travel")
			var chest: Array = art.DATA[art.clip].chest[art.source_frame]
			var chest_local := (Vector2(chest[0],chest[1])-Vector2(128,128))*Vector2(facing,1)
			check(art.to_global(chest_local).distance_to(deer.global_position+deer.core_offset())<.01,"Chest warning follows rendered chest in both directions")
			if DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("authored_%s_%d.png" % [sample[0],int(facing)]))
	var seen := {}
	for i in 100:
		deer._sample_pose(&"leap_turn_ING",i/100.0,1.0)
		seen[art.source_frame] = true
	check(seen.size()==10,"All ten airborne poses play despite the old clip having fewer frames")
	deer._show_clip_at(&"idle_ING",1.5,-1,true)
	check(art.source_frame==15,"Authored idle retains 100 ms source timing")
	deer._show_clip_at(&"idle_ING",1.6,-1,true)
	check(art.source_frame==0,"Idle loops at its own 16-frame boundary")
	deer._show_clip(&"walk_ING",2)
	check(art.visible and art.clip==&"walk_ING" and deer.animated_sprite.self_modulate.a==0,"Walking no longer falls back to the old body")
	deer._show_clip_at(&"walk_ING",24.0/14.0,14,true)
	check(art.source_frame==0,"Walking loops only the 24 gait frames, not the standing bookends")
	# A real break uses fall/hold/rise in the original guaranteed opening.
	deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
	var original_opening := deer.opening
	deer._update_opening(.2)
	check(deer._break_pose and art.clip==&"weak_START","Real poise depletion starts authored collapse")
	deer._update_opening(.2)
	check(art.clip==&"weak_ING","Broken boss holds the authored prone pose")
	deer._update_opening(original_opening-.4-.30)
	check(art.clip==&"weak_END","Rise plays forward at the end of the existing opening")
	deer._update_opening(.31)
	check(deer.opening==0 and not deer._break_pose,"New weakness art does not extend the opening")
	deer.restart_duel()
	check(not deer._break_pose,"Reset clears weakness playback")
	deer._on_health_depleted()
	check(art.clip==&"weak_ING" and deer._stopped,"Defeat remains down in the new body without playing a rise")
	deer._show_clip(&"idle_ING",0)
	deer.animated_sprite.modulate = Color(.8,.3,.2,.5)
	check(art.modulate==Color.WHITE and art.is_visible_in_tree(),"Shared hit feedback reaches replacement body")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER AUTHORED BODY")

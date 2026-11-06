extends "../../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var room: Chapter1DeerBossRoom=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro:=WindSightingComic.new()
	var packed:=PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	var player:=room.player
	player.set_physics_process(false)
	for phase in range(1,5):
		room.encounter._spawn_phase(phase,1420)
		room.encounter.start()
		var boss:=room.deer
		boss.set_physics_process(false)
		boss.manual_control=true
		boss.invulnerable=false
		player.reset_after_map_fall(Vector2(1200,555))
		player.set_physics_process(false)
		# Reproduce production: no separation target, automatically named hurt shape.
		player.separation_target=null
		var hp:=boss.combat_stats.health
		player.arm_ultimate()
		check(player.ultimate_magic_circle.visible and is_equal_approx(player.get_action_time_scale(),1.25),"Phase %d first cast enables circle and haste"%phase)
		player.start_ultimate_combo()
		check(player.ultimate.ultimate_target==boss,"Phase %d selects the live production actor without movement target"%phase)
		check(not player.ultimate_armed and is_equal_approx(player.get_action_time_scale(),1),"Early second stage ends haste immediately")
		for f in 300:
			player.update_ultimate_combo(1.0/60)
			await physics_frame
			if not player.ultimate_active: break
		check(boss.combat_stats.health<hp,"Phase %d ultimate deals actual health damage (%d)"%[phase,hp-boss.combat_stats.health])
		check(not player.ultimate_active and player.collision_mask!=0,"Stage two finishes and restores collision")
		await wait_frames(40)
	player.reset_after_map_fall(Vector2(1200,555))
	player.arm_ultimate()
	player.update_ultimate_activation(7.5)
	check(player.ultimate_armed and player.ultimate_magic_circle.visible,"Magic circle persists beyond its original five-second window")
	check(is_equal_approx(player.animated_sprite.speed_scale,player.body_base_speed*1.25) and is_equal_approx(player.combat_timeline.speed_scale,player.timeline_base_speed*1.25),"Body and combat timeline share haste")
	if DisplayServer.get_name()!="headless":
		await wait_frames(30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("lan_haste_circle.png"))
	player.update_ultimate_activation(.51)
	check(player.ultimate_active and not player.ultimate_magic_circle.visible and player.get_action_time_scale()==1,"Expiry automatically releases stage two and stops circle/haste")
	player.reset_after_map_fall(Vector2(1200,555))
	player.arm_ultimate()
	player.reset_after_map_fall(Vector2(1200,555))
	check(not player.ultimate_active and not player.ultimate_armed and player.get_action_time_scale()==1,"Retry clears both stages and restores speed")
	# CharacterBody movement must use the same clock, not only faster animations.
	player.velocity=Vector2(300,0)
	var x:=player.position.x
	player.move_on_action_clock()
	var baseline:=player.position.x-x
	player.arm_ultimate()
	player.velocity=Vector2(300,0)
	x=player.position.x
	player.move_on_action_clock()
	check(is_equal_approx((player.position.x-x)/baseline,1.25),"Movement distance uses the same 25 percent haste")
	player.disarm_ultimate()
	player.reset_after_map_fall(Vector2(1200,555))
	player.input_frozen=false
	player.arm_ultimate()
	for f in 60: player._physics_process(1.0/60)
	check(is_equal_approx(player.ultimate_window_remaining,7),"Haste duration uses elapsed seconds rather than its accelerated action clock")
	player.disarm_ultimate()
	expect_save_untouched()
	finish("DEER LAN ULTIMATE")

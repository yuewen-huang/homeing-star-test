extends "../support/harness.gd"

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await wait_frames(45)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	var save := use_memory_progress()
	remove_meta(&"suppress_combat_lesson_videos")
	var alley := load("res://scenes/levels/back_alley/back_alley.tscn").instantiate() as Node2D
	root.add_child(alley)
	current_scene = alley
	await process_frame
	var encounter: Node = alley.encounter
	encounter.set_process(false)
	alley.player.set_physics_process(false)
	alley.player.position.x = encounter.trigger_x
	alley._process(0)
	encounter._begin_ambush()
	check(not paused and encounter.dialogue.opened, "Story dialogue comes before the first demonstration")
	while encounter.dialogue != null and encounter.dialogue.opened: encounter.dialogue.advance()
	encounter._process(0)
	check(paused and encounter.lesson_player.lesson_id == &"normal_attack", "First wave opens its video after dialogue")
	check(encounter.lesson_player.video.stream.resource_path == CombatLessonCatalog.video_path(&"normal_attack"), "Alley introduction selects alley footage")
	await capture("back_alley_normal_lesson")
	encounter.lesson_player.close_lesson(true)
	check(not save.has_completed(SaveProgressService.STORY_BACK_ALLEY_WAVE_1_CLEARED), "Skipping video does not clear wave one")
	check(encounter.key_hint.pending_labels == ["J"], "World resumes with the overhead J key")
	for wave in [2, 3, 4]:
		for enemy: Node in encounter.live_enemies:
			if is_instance_valid(enemy): enemy.free()
		encounter.live_enemies.clear()
		encounter._start_next_wave(wave)
		await process_frame
		encounter._process(0)
		check(paused and encounter.lesson_player.lesson_id == [&"instant_dash", &"jump_attack", &"dodge_combo"][wave - 2], "Wave %d opens its own real-action video" % wave)
		encounter.lesson_player.close_lesson(true)
	for enemy: Node in encounter.live_enemies:
		if is_instance_valid(enemy): enemy.free()
	encounter.live_enemies.clear()
	encounter._enter_fifth_wave()
	await process_frame
	encounter._process(0)
	check(paused and encounter.lesson_player.lesson_id == &"charged_attack", "Frog wave introduces charged attack")
	await capture("back_alley_frog_lesson")
	encounter.lesson_player.close_lesson(true)
	check(not save.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_NORMAL_USED), "Video does not pretend a heavy attack landed")
	encounter._on_frog_special_attack_received(false, false)
	encounter.frog_boss.combat_stats.apply_poise_damage(encounter.frog_boss.combat_stats.max_poise)
	encounter._refresh_special_tutorial_hint()
	await process_frame
	encounter._process(0)
	check(paused and encounter.lesson_player.lesson_id == &"poise_throw", "Actual broken poise introduces throw")
	encounter.lesson_player.close_lesson(true)
	check(encounter.key_hint == null, "Lan's existing E keycap owns the throw prompt")
	check(not save.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_TUTORIAL_COMPLETE), "Viewing the throw does not finish the skill challenge")
	current_scene = null
	alley.free()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var teaching := room.get_node("MasterCombatTeaching")
	var master := room.get_node("MasterBoss") as MasterBoss
	var lan := room.get_node("Lan") as LanPlayer
	await wait_frames(3)
	check(not paused and teaching._pending.is_empty(), "Retired phase-one attacks queue no opening demonstration")
	teaching.set_process(false)
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	lan.set_physics_process(false)
	master.state = MasterBoss.State.PHASE_2_ATTACK
	master.phase = 2
	master.animated_sprite.animation = &"phase_2_special_attack"
	master.active_attack_danger_type = CombatAttackData.DangerType.UNPARRYABLE_DANGER
	teaching._pending.clear()
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["L"] and teaching.key_hint.visible, "Live combat uses an overhead L without a text banner")
	check(teaching.find_children("*", "ScreenNotice", true, false).is_empty(), "Master teaching owns no full-screen text notice")
	current_scene = null
	room.free()
	check(not paused, "Leaving the tutorial does not strand a pause")
	expect_save_untouched()
	finish("COMBAT LESSON TRIGGERS")

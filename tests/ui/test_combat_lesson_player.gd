extends "../support/harness.gd"

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	var save := use_memory_progress()
	remove_meta(&"suppress_combat_lesson_videos")
	for id: StringName in CombatLessonCatalog.LESSONS:
		check(FileAccess.file_exists(CombatLessonCatalog.video_path(id)), "Video exists: %s" % id)
	check(FileAccess.file_exists(CombatLessonCatalog.video_path(&"poise_throw", true)), "Master has a separate throw recording")
	check(CombatLessonCatalog.video_path(&"poise_throw", true) != CombatLessonCatalog.video_path(&"poise_throw"), "Throw footage follows the current encounter")
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	var lan := room.get_node("Lan") as LanPlayer
	var master := room.get_node("MasterBoss") as MasterBoss
	var modal := CombatLessonPlayer.new()
	room.add_child(modal)
	check(not modal.show_lesson(&"normal_attack", true), "Alley demonstration cannot run as a master lesson")
	check(not modal.show_lesson(&"parry", false), "Master demonstration cannot run in the alley")
	save.finish_cinematic(&"combat_lesson_normal_attack", true)
	check(modal.show_lesson(&"normal_attack"), "First lesson opens")
	check(paused and modal.opened and modal.video.is_playing(), "World pauses while video plays")
	check(not lan.input_frozen, "Modal preserves player action state")
	var point := lan.position
	var anim_frame := master.animated_sprite.frame
	var cooldown := lan.instant_dash_cooldown_remaining
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var feedback_clock: float = feedback._real_clock
	await wait_frames(45)
	check(lan.position == point and master.animated_sprite.frame == anim_frame, "Actors stay frozen")
	check(lan.instant_dash_cooldown_remaining == cooldown and feedback._real_clock == feedback_clock, "Combat clocks stay frozen")
	check(modal.video.stream_position > 0, "Video advances in the paused tree")
	await capture("combat_lesson_left")
	modal.close_lesson(true)
	check(not paused and not modal.opened, "Close restores world pause state")
	check(save.get_cinematic_status(CombatLessonCatalog.record_id(&"normal_attack")) == SaveProgressService.CinematicStatus.SKIPPED, "Explicit skip has its own viewing record")
	check(not save.has_completed(SaveProgressService.STORY_BACK_ALLEY_WAVE_1_CLEARED), "Watching does not clear the encounter")
	check(not modal.show_lesson(&"normal_attack"), "Handled video does not interrupt again")
	check(modal.show_lesson(&"parry", true), "Master lesson opens")
	await wait_frames(45)
	check(modal.dialogue._portrait.texture == CombatLessonCatalog.MASTER, "Master uses prepared right portrait")
	await capture("combat_lesson_right")
	var other := CombatLessonPlayer.new()
	room.add_child(other)
	check(not other.show_lesson(&"gold_dodge", true, true), "Nested modal cannot steal pause ownership")
	await wait_frames(ceili(modal.video.get_stream_length() * 60.0) + 2)
	modal.close_lesson()
	check(save.get_cinematic_status(CombatLessonCatalog.record_id(&"parry")) == SaveProgressService.CinematicStatus.WATCHED, "Completed viewing record is separate from battle facts")
	paused = true
	check(modal.show_lesson(&"gold_dodge", true, true), "Can present inside an existing pause")
	modal.close_lesson(true)
	check(paused, "Closing preserves a pre-existing pause")
	paused = false
	check(modal.show_lesson(&"red_parry", true, true), "Open before scene cleanup")
	modal.free()
	check(not paused and not has_meta(&"combat_lesson_owner"), "Scene cleanup releases its pause")
	check(not CombatLessonCatalog.handled(save, &"red_parry"), "Interrupted presentation does not write viewing completion")
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("COMBAT LESSON PLAYER")

extends "../../support/harness.gd"

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await wait_frames(45)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	var save := use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await wait_frames(2)
	var master := room.get_node("MasterBoss") as MasterBoss
	var lan := room.get_node("Lan") as LanPlayer
	var teaching := room.get_node("MasterCombatTeaching")
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	lan.set_physics_process(false)
	teaching.set_process(false)
	teaching._offer(&"gold_dodge")
	master._enter_phase_2()
	check(teaching._pending.is_empty(), "Transformation removes stale first-form demonstrations")
	teaching._offer(&"phase_2_slash")
	teaching._process(0)
	check(not teaching.lesson_player.opened, "Transformation finishes before any lesson pauses the scene")
	master._enter_phase_2_idle(100)
	remove_meta(&"suppress_combat_lesson_videos")
	teaching._seen.append(&"sobering")
	for pair in [[&"phase_2_attack_1", &"phase_2_slash"], [&"phase_2_attack_2", &"phase_2_combo"], [&"phase_2_dash", &"phase_2_red_dash"], [&"phase_2_uppercut", &"phase_2_wave"]]:
		teaching._pending.clear()
		master.phase_2_finale_active = false
		master.phase_2_buff_remaining = 5
		master._start_phase_2_attack(pair[0])
		teaching._process(0)
		check(paused and teaching.lesson_player.lesson_id == pair[1], "Actual %s triggers its own second-form video" % pair[0])
		check(teaching.key_hint.pending_labels == ["K"], "Attack prompt takes priority over item use")
		if pair[0] == &"phase_2_attack_2": await capture("phase_2_combo_lesson")
		teaching.lesson_player.close_lesson(true)
	teaching._pending.clear()
	master.phase_2_finale_active = true
	master._start_phase_2_attack(&"phase_2_dash")
	teaching._process(0)
	check(paused and teaching.lesson_player.lesson_id == &"phase_2_gold_chain", "Gold pursuit gets a separate demonstration")
	check(teaching.key_hint.pending_labels == ["L"], "Gold warning prompts dodge before its first damage frame")
	await capture("phase_2_gold_chain_lesson")
	teaching.lesson_player.close_lesson(true)
	master._start_phase_2_attack(&"phase_2_special_attack")
	teaching._process(0)
	check(not paused and teaching.key_hint.pending_labels == ["L"], "Second gold action keeps the dodge prompt without another interruption")
	master._enter_phase_2_idle(100)
	master.phase_2_finale_active = false
	var wave := MasterGroundWave.new()
	room.add_child(wave)
	wave.global_position = lan.global_position - Vector2(200, 0)
	wave.launch(1, -1280, 1280, lan.hurtbox, master)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["W", "W"], "An approaching ground wave prompts a double jump")
	wave.free()
	master._start_phase_2_howl()
	check(teaching.lesson_player.show_lesson(&"sobering", true, true), "Howl lesson can be reviewed without an item")
	check(teaching.lesson_player.dialogue._label.text.contains("没带"), "Missing item has an evasive fallback")
	check(save.get_item_count(ItemCatalog.HANGOVER_PILL) == 0, "Guidance does not grant the item")
	teaching.lesson_player.close_lesson(true)
	save.add_item(ItemCatalog.HANGOVER_PILL)
	teaching.lesson_player.show_lesson(&"sobering", true, true)
	check(teaching.lesson_player.dialogue._label.text.contains("B") and teaching.lesson_player.dialogue._label.text.contains("装配"), "Owned unequipped pill explains the inventory step")
	teaching.lesson_player.close_lesson(true)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["B"], "Howl prompts inventory when the pill is unequipped")
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
	teaching.lesson_player.show_lesson(&"sobering", true, true)
	check(teaching.lesson_player.dialogue._label.text.contains("Q"), "Equipped pill lesson uses the actual key binding")
	await capture("phase_2_sobering_lesson")
	teaching.lesson_player.close_lesson(true)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["Q"], "Howl prompts Q when the pill is ready")
	room._on_special_item_use_requested(ItemCatalog.HANGOVER_PILL)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["J", "I"], "Successful sobering immediately prompts a real punish")
	master.combat_stats.apply_poise_damage(master.combat_stats.max_poise)
	teaching._pending.clear()
	teaching._process(0)
	await process_frame
	teaching._process(0)
	check(paused and teaching.lesson_player.lesson_id == &"phase_2_poise_throw", "Second-form poise break uses second-form throw footage")
	teaching.lesson_player.close_lesson(true)
	master.poise_broken = false
	master.combat_stats.restore_poise()
	master.sobering_remaining = 0
	master.phase_2_buff_remaining = 0
	master.phase_2_finale_active = false
	master._enter_phase_2_idle(100)
	teaching._pending.clear()
	save.try_complete_fact(SaveProgressService.STORY_MASTER_ULTIMATE_LEARNED)
	lan.combat_stats.add_mana(100)
	teaching._process(0)
	await process_frame
	teaching._process(0)
	check(paused and teaching.lesson_player.lesson_id == &"ultimate", "Actual ultimate unlock triggers the second-form demonstration")
	check(teaching.key_hint.pending_labels == ["O"], "Full mana prompts O in an open punish window")
	teaching.lesson_player.close_lesson(true)
	check(not save.has_completed(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), "Watching does not settle victory")
	current_scene = null
	room.free()
	check(not paused, "Leaving the scene releases presentation pause")
	expect_save_untouched()
	finish("MASTER PHASE TWO TEACHING")

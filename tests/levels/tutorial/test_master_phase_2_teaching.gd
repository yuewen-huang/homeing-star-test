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
	var duel := lan.pulse_duel
	check(master.combat_stats.max_health == 1200, "First master bar uses the standard budget")
	duel.player_energy = 37
	duel.boss_internal_hp = 30
	teaching._offer(&"gold_dodge")
	master._enter_phase_2()
	if master.phase == 1: master._start_phase_2_transformation() # Advance the spoken intro cue with AI paused.
	check(master.combat_stats.health == 1500 and master.combat_stats.max_health == 1500,
		"Master transformation restores a full second bar")
	check(lan.pulse_duel == duel and duel.player_energy == 37 and duel.boss_internal_hp == 0,
		"Master transformation keeps Lan's energy and clears the former wound")
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
	master.start_phase_2_body_action(MasterPhase2BodyAction.PRESSURE_FIVE)
	var action := master.phase_2_body_action
	action.advance(action._gold_prepare_at)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["L"], "Near five switches to dodge during the gold claw's raised-arm preparation")
	action.advance(action._gold_end_at - action.elapsed + .02)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["K"], "After gold, the remaining near-five uppercut offers parry")
	# The high-buff scene normally offers the equipped pill. Reuse a separate
	# memory-only save for this check so later inventory cases start empty.
	var inventory := save._config
	save._config = ConfigFile.new()
	save.add_item(ItemCatalog.HANGOVER_PILL)
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
	action.advance(float(action.data.duration))
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["J", "I"], "Visible settle shows the punish prompt ahead of the ready pill")
	save._config = inventory
	teaching._pending.clear()
	master.manual_control = true
	master.movement_direction = -1.0
	lan.position.x = master.position.x - 110.0
	master.start_phase_2_body_action(MasterPhase2BodyAction.RISING_QUAKE)
	var quake := master.phase_2_body_action
	teaching._process(0)
	check(paused and teaching.lesson_player.lesson_id == &"phase_2_quake",
		"The body-action quake opens the actual claw-and-jump lesson")
	await capture("phase_2_quake_lesson")
	teaching.lesson_player.close_lesson(true)
	quake.advance(quake._gold_prepare_at + .03)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["L"], "The sustained gold claws offer dodge")
	quake.advance(quake._gold_end_at - quake.elapsed + .10)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["W"], "The ground brace switches from dodge to a separate jump cue")
	quake.advance(float(quake.data.duration))
	teaching._process(0)
	check(teaching.key_hint.pending_labels == ["J", "I"], "Settling after the travelling front offers a punish")
	master.manual_control = false
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
	master.charged_power = 4
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
	check(master.charged_power == 1 and master.state == MasterBoss.State.PHASE_2_HOWL, "Sobering removes three stacks and leaves the howl running")
	check(teaching.key_hint.pending_labels == ["Q"], "After a partial sober the howl still offers another pill use")
	master.combat_stats.apply_poise_damage(master.combat_stats.max_poise)
	teaching._pending.clear()
	teaching._process(0)
	await process_frame
	teaching._process(0)
	check(not master.poise_broken and not teaching._pending.has(&"phase_2_poise_throw"), "Second-form defense never queues the removed break lesson")
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
	check(teaching.lesson_player.lesson_id == &"ultimate" and paused, "The unlocked once-per-fight ultimate gets its lesson")
	teaching.lesson_player.close_lesson(true)
	lan.pulse_duel.player_energy = 100
	lan.position = master.position + Vector2(64, 0)
	teaching._process(0)
	check(teaching.key_hint.pending_labels == [KeyHint.resolve_action_key_label(&"interact")], "Full energy prompts a nearby burst in an open punish window")
	teaching.lesson_player.close_lesson(true)
	check(not save.has_completed(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), "Watching does not settle victory")
	current_scene = null
	room.free()
	check(not paused, "Leaving the scene releases presentation pause")
	expect_save_untouched()
	finish("MASTER PHASE TWO TEACHING")

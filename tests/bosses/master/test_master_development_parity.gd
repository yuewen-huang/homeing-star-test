extends "../../support/harness.gd"
var room: BossDevelopmentRoom

func tick_to(time: float) -> void:
	var master: MasterBoss = room.adapter.master
	var guard := 0
	while master.clash_rhythm != null and master.clash_rhythm.elapsed + 0.000001 < time and guard < 4000:
		master._process(minf(1.0 / 120, time - master.clash_rhythm.elapsed))
		room._physics_process(0)
		guard += 1
	check(guard < 4000, "Preview clock reaches the requested action time")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func run() -> void:
	var save := use_memory_progress()
	var progress_before := save._config.encode_to_text()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	var formal := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	var expected_scale := (formal.get_node("MasterBoss") as Node2D).scale
	formal.free()
	check(room.adapter.master.scale == expected_scale, "Development master inherits the production encounter scale")
	check(room.combo_picker.item_count == 3 and not room.segment_row.visible, "Formal combat and source-art modes are separate")
	var observer_health := room.player.combat_stats.health
	check(room.library_picker.visible == false, "The five-move table needs no secondary move picker")
	check(room.adapter.action_names().size() == 4 and not room.ultimate_button.visible and room.blade_button.visible and room.smear_button.visible,
		"Four formal actions omit the retired return chain while preserving independent ultimate and combo shortcuts")
	room.play_action(4)
	check(room.adapter.master.clash_rhythm == null, "The retired fifth action shortcut cannot index outside the four-move table")
	check(not MasterClashRhythm.RHYTHMS.has(&"return_chain"), "The retired return chain cannot be started as a production rhythm")
	for i in MasterClashRhythm.ORDER.size():
		room.play_action(i)
		var master: MasterBoss = room.adapter.master
		master.set_process(false)
		master.attack_hitbox.set_physics_process(false)
		check(master.clash_rhythm is MasterClashRhythm and master.clash_rhythm.id == MasterClashRhythm.ORDER[i], "Button starts production rhythm %s" % MasterClashRhythm.ORDER[i])
		check(not master.combat_timeline.is_playing() and master.phase_1_motion == null, "Formal preview does not use a legacy timeline or source-art track")
		check(master.manual_control and master.combat_target != room.player, "Preview stays manual and targets the dummy")
		var rhythm: MasterClashRhythm = master.clash_rhythm
		var duration := rhythm.duration
		tick_to(float(rhythm.strikes[0].t) - 0.15)
		if i in [0, 4]: await capture("rhythm_%d_warning" % i)
		tick_to(float(rhythm.strikes[0].t) + 0.02)
		check(master.attack_hitbox.attack != null, "Production damage window opens on the first rhythm beat")
		check(room.adapter.action_sample().clip == String(rhythm.id), "Readout reports the live production rhythm")
		if i in [0, 4]: await capture("rhythm_%d_active" % i)
		tick_to(duration - 0.01)
		if i in [0, 4]: await capture("rhythm_%d_recovery" % i)
		check(not room.dummy.contacts.is_empty(), "Production probes reach the dummy for %s" % rhythm.id)
		if rhythm.id == &"air_qi_combo":
			check(rhythm is MasterAnnotatedCombo and rhythm.strikes.size() == 8 and rhythm.projectiles.is_empty(),
				"The aerial slot plays the reviewed eight-cut melee string")
	room.select_combo(2)
	check(room.segment_row.visible and room.adapter.action_names()[0].contains("旧稿"), "Legacy material is clearly labeled and exposes source segments only here")
	room.play_action(0)
	check(room.adapter.master.clash_rhythm == null and room.adapter.master.combat_timeline.is_playing(), "Legacy action is available only in its source-preview mode")
	room.select_combo(1)
	room.select_combo_library(5)
	room.play_action(4)
	check(room.adapter.master.phase_2_buff_remaining > 0 and room.adapter.master.body_base_speed == MasterBoss.PHASE_2_BUFF_ATTACK_MULTIPLIER, "Second-phase buffed combo uses the production speed multiplier")
	check(room.item_button.visible, "Second phase exposes the temporary sobering item")
	room.item_available.button_pressed = false
	check(not room.use_preview_item(), "Missing preview item cannot clear the buff")
	room.item_available.button_pressed = true
	check(room.use_preview_item() and room.adapter.master.sobering_remaining > 0 and room.adapter.master.phase_2_buff_remaining == 0, "Preview pill calls the real sobering recovery")
	await capture("phase_2_sobered")
	check(room.player.combat_stats.health == observer_health and not room.player.input_frozen, "Observer remains safe and controllable")
	room.reset_room()
	check(room.library_picker.selected == 5 and room.adapter.library_index == 5, "Reset preserves the selected move in the restored phase library")
	check(room.adapter.master.phase == 2 and room.adapter.master.phase_2_buff_remaining == 0 and not room.adapter.master.can_use_sobering_item(), "Reset preserves phase but clears temporary combat state")
	check(room.specimen.get_child_count() == 2, "Reset clears old smears, projectiles and specimens")
	check(save._config.encode_to_text() == progress_before, "Development actions and pill do not write progress or inventory")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("MASTER DEVELOPMENT PARITY")

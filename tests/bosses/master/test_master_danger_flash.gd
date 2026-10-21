extends "../../support/harness.gd"
## Both production forms use the deer's shared chest glint, including phase-two
## red teleport, gold pursuit and the pursuit's gold follow-up.
var master: MasterBoss

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func check_cue(kind: StringName) -> void:
	master._update_danger_flash(0.06)
	var cue := master.danger_flash
	check(cue != null and cue.visible and cue.kind == kind, "The actual move shows its shared %s cue" % kind)
	check(not master.danger_warning.visible and not master.danger_warning.is_playing(), "The legacy warning strip stays stopped and hidden")
	check(cue.frame == DangerFlash.frame_at(0.06), "Frame timing matches the deer's cue")
	var baked := cue.pieces.size() == 2 and not cue.pieces[0]._clip.is_empty() and not cue.pieces[1]._clip.is_empty()
	check(baked and cue.position == master.RED_COUNTER_SLASH_POINT, "Shared production atlases are anchored at the master's chest")
	check(cue.pieces[0].shape == &"star" and cue.pieces[1].spark_converge, "The cue is the four-point star and converging shards")

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(true)
	var room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.get_node("MasterBoss")
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	room.get_node("Lan").set_physics_process(false)
	for kind: StringName in [&"red", &"gold"]:
		master.flash_danger(kind)
		check_cue(kind)
		await capture("phase_1_%s" % kind)
	master.parry_pause_remaining = 0.1
	var held_age := master._danger_flash_age
	master._process(0.02)
	check(is_equal_approx(master._danger_flash_age, held_age), "Parry hit-stop freezes the danger cue with the boss action")
	master.parry_pause_remaining = 0.0
	master._enter_phase_2()
	check(not master.danger_flash.visible, "Transformation clears first-form cues")
	for difficulty in [BattleAssistSettingsService.Difficulty.NORMAL, BattleAssistSettingsService.Difficulty.NIGHTMARE]:
		assist.set_difficulty(difficulty)
		for spec in [[false, &"phase_2_dash", &"red"], [true, &"phase_2_dash", &"gold"], [true, &"phase_2_special_attack", &"gold"]]:
			for facing in [-1.0, 1.0]:
				master._enter_phase_2_idle(100)
				master.movement_direction = facing
				master.phase_2_finale_active = spec[0]
				master._start_phase_2_attack(spec[1])
				master.animated_sprite.pause()
				check_cue(spec[2])
				check((master.danger_flash.scale.x < 0.0) == (facing < 0.0), "The chest glint mirrors for both facings, including nightmare")
				await capture("phase_2_%s_%s_%s" % [spec[2],spec[1],"left" if facing < 0 else "right"])
				master.animated_sprite.hide()
				master._update_danger_flash(0)
				check(not master.danger_flash.visible, "Teleport invisibility hides the glint with the body")
				master.animated_sprite.show()
				master._update_danger_flash(0)
				check(master.danger_flash.visible, "Visibility changes do not expire a still-live cue")
				master._update_danger_flash(0.31)
				check(not master.danger_flash.visible, "The shared flash expires after its curve")
				master.animated_sprite.frame = 6
				await capture("phase_2_%s_active" % spec[2])
				master.flash_danger(spec[2])
				master._interrupt_phase_2_action(1.0)
				check(not master.danger_flash.visible, "Interruptions clear the chest cue")
				await capture("phase_2_%s_recovery" % spec[2])
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER DANGER FLASH")

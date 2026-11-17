extends "../../support/harness.gd"
var boss: MasterBoss
var lan: LanPlayer

func reset(buffed: bool, finale: bool, facing: float) -> void:
	boss._interrupt_phase_2_action(0)
	boss.action_clock.clear()
	boss.phase_2_buff_remaining = 8.0 if buffed else 0.0
	boss.phase_2_finale_active = finale
	boss.position = Vector2(0,555)
	boss.movement_direction = facing
	boss.combat_stats.restore_poise()
	boss.poise_broken = false
	lan.reset_after_map_fall(Vector2(facing*115,555))
	lan.combat_stats.restore_health()
	lan.combat_stats.restore_stamina(100)
	Engine.time_scale = 1

func press_l() -> void:
	lan.dodge_input_buffer_remaining = lan.COMBAT_INPUT_BUFFER
	lan.dodge_buffer_direction = -boss.movement_direction
	lan._physics_process(0)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	boss = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	boss.manual_control = true
	boss.set_process(false)
	lan.set_physics_process(false)
	await process_frame
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	boss._enter_phase_2()
	# Every dangerous group, both facings, all difficulties, regular and gold finale.
	for difficulty in [0,1,2]:
		assist.set_difficulty(difficulty)
		for buffed in [false,true]:
			for facing in [-1.0,1.0]:
				for id: StringName in MasterPhase2BodyAction.IDS:
					for finale in [false,true]:
						reset(buffed,finale,facing)
						boss.start_phase_2_body_action(id)
						var action := boss.phase_2_body_action
						var first_release := INF
						var at := 0.0
						for clip: Dictionary in action.data.clips:
							for group: Dictionary in clip.groups:
								for member: Dictionary in group.members:
									first_release = minf(first_release, at + float(member.release) - float(clip.start_time))
							at += float(clip.duration)
						var groups := action._danger_groups.duplicate(true)
						for index in groups.size():
							reset(buffed,finale,facing)
							boss.start_phase_2_body_action(id)
							action = boss.phase_2_body_action
							var row: Dictionary = action._danger_groups[index]
							var expected_beat := float(row.release) > first_release + .000001
							check(bool(row.beat)==expected_beat, "%s group %d uses opener/full or continuation/beat" % [id,index])
							var speed := boss.get_phase_2_attack_speed()
							var peak := float(row.release)-DangerFlash.DODGE_LEAD*speed
							boss._process(peak/speed)
							check(boss.danger_flash != null and boss.danger_flash.visible and is_equal_approx(boss._danger_flash_age,DangerFlash.PEAK_TIME), "%s group %d has a visible peak 100 ms before release" % [id,index])
							check(boss.danger_flash.beat==expected_beat, "%s group %d displays the intended cue mode" % [id,index])
							var expected_kind: StringName = &"gold" if int(row.danger)==CombatAttackData.DangerType.UNPARRYABLE_DANGER else &"red"
							check(boss.danger_flash.kind==expected_kind, "%s group %d shows the matching danger colour" % [id,index])
							boss._interrupt_phase_2_action(0)
							await process_frame
	# The live claw and the jumpable ground front have distinct cues.
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	reset(false, true, 1)
	boss.start_phase_2_body_action(MasterPhase2BodyAction.RISING_QUAKE)
	var ground_action := boss.phase_2_body_action
	ground_action.advance(ground_action._gold_end_at + .10)
	var warning := ground_action.vfx._quake_warning
	check(warning._used == 1 and (boss.danger_flash == null or not boss.danger_flash.visible),
		"The post-claw brace marks the ground without another chest flash")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	ground_action.advance(.04)
	check(warning._used == 0 and boss.animated_sprite.animation == &"phase_2_special_attack"
		and boss.animated_sprite.frame == 15, "Nightmare hides the range strip and keeps the tucked landing pose")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	ground_action.advance(.57)
	check(warning._used == 0, "The travelling front takes over from the floor strip")
	boss._interrupt_phase_2_action(0)
	# The ninth flying sword is a short gold beat.
	reset(false,false,1)
	boss.phase = 1
	var formation := MasterFlyingSwordFormation.new()
	boss.add_child(formation)
	formation.setup(boss,lan)
	formation.self_stepping = false
	formation.combat = MasterFlyingSwordCombat.new()
	formation.combat.boss = boss
	formation.rage(lan.global_position+Vector2(0,-48))
	var found := false
	for tick in 1400:
		formation.advance(1.0/240.0)
		if boss.danger_flash != null and boss.danger_flash.visible and absf(boss._danger_flash_age-DangerFlash.PEAK_TIME)<1.0/240.0:
			found = true
			break
	check(found and boss.danger_flash.kind==&"gold" and boss.danger_flash.beat, "Ninth flying sword shows a short gold beat")
	formation.queue_free()
	# Both modes rise to one peak and retain the baked pieces and shader.
	for beat in [false,true]:
		boss.show_danger_at(&"gold",DangerFlash.PEAK_TIME,beat)
		var cue := boss.danger_flash
		var peak_alpha := cue.pieces[0].modulate.a
		for time in [DangerFlash.start_age(beat),DangerFlash.PEAK_TIME-.01,DangerFlash.PEAK_TIME+.01,.34]:
			cue.show_at(time,1,Vector2.ZERO)
			check(cue.pieces[0].modulate.a<peak_alpha, "Star brightness is lower outside the peak")
		check(not cue.pieces[0]._clip.is_empty() and not cue.pieces[1]._clip.is_empty() and cue.flare.material.shader==DangerFlash.FLARE_SHADER, "Cue retains baked art and flare")
	expect_save_untouched()
	finish("MASTER DODGE CUES")

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
			var speed := 1.4 if buffed else 1.0
			for facing in [-1.0,1.0]:
				for id: StringName in MasterPhase2BodyAction.IDS:
					for finale in [false,true]:
						reset(buffed,finale,facing)
						boss.start_phase_2_body_action(id)
						var groups := boss.phase_2_body_action._danger_groups.duplicate(true)
						for row: Dictionary in groups:
							reset(buffed,finale,facing)
							boss.start_phase_2_body_action(id)
							var action := boss.phase_2_body_action
							# Replays use their newly assigned serial, not the prior action's key.
							var current: Dictionary = action._danger_groups[groups.find(row)]
							var peak := float(current.release)-DangerFlash.DODGE_LEAD*speed
							boss._process(peak/speed)
							check(boss.danger_flash != null and is_equal_approx(boss._danger_flash_age,DangerFlash.PEAK_TIME), "Danger peak follows authored attack clock")
							press_l()
							check(lan.ground_action_state==LanPlayer.GroundActionState.BACK_DODGE, "Peak L enters dodge through normal input buffer")
							boss._process((float(current.release)-action.elapsed+.001)/speed)
							var contacts := 0
							for box: CombatHitbox2D in action.hitboxes.values():
								if box.attack.evasion_key != current.key: continue
								contacts += 1
								check(lan.hurtbox.receive_attack(box.attack)==CombatHitResult.Type.EVADED, "Peak L evades the corresponding real attack data")
							check(contacts>0,"Announced attack exists at release")
							if finale:
								check(int(current.danger)==CombatAttackData.DangerType.UNPARRYABLE_DANGER,"Entire finale, including its first strike, is gold")
							boss._interrupt_phase_2_action(0)
							await process_frame
	# Physical collision replay for the previously unfair first gold uppercut.
	for buffed in [false,true]:
		for facing in [-1.0,1.0]:
			reset(buffed,true,facing)
			boss.start_phase_2_body_action(&"master_phase2_rising_quake")
			var action := boss.phase_2_body_action
			var speed := 1.4 if buffed else 1.0
			var ground: Dictionary = {}
			var pressed := false
			for tick in 1200:
				boss._process(1.0/240.0)
				for row: Dictionary in action.vfx.effects.values():
					if row.event.do != "quake": continue
					ground = row
					for cue: Dictionary in action.vfx.ground_cues():
						var peak := float(cue.release)-DangerFlash.DODGE_LEAD*speed
						if action.elapsed>=peak and action.elapsed<peak+speed/240.0+.00001:
							press_l()
							pressed = true
				if pressed: break
			check(pressed,"Travelling ground front has its own input peak")
			if pressed:
				lan.combat_timeline.seek(.3*lan.BACK_DODGE_SPEED_SCALE,true)
				boss.manual_control = false
				var rect := CombatHitQuery.hurtbox_rect(lan)
				var at := Vector2(clampf(ground.effect.global_position.x,rect.position.x,rect.end.x),boss.global_position.y)
				var arrival: float = ground.effect.arrival(action.vfx._ground_point(ground,at))
				action.vfx._resolve_ground(ground,arrival-.001,arrival+.001)
				check(lan.combat_stats.health==100 and ground.hit_targets.has(lan.get_instance_id()),"Peak claim covers late ground contact exactly once")
				boss.manual_control = true
			boss._interrupt_phase_2_action(0)
			await process_frame
	# Flying-sword rage ninth cut uses the same visible peak and attack key.
	reset(false,false,1)
	boss.phase = 1
	var formation := MasterFlyingSwordFormation.new()
	boss.add_child(formation)
	formation.setup(boss,lan)
	formation.self_stepping = false
	formation.combat = MasterFlyingSwordCombat.new()
	formation.combat.boss = boss
	formation.rage(lan.global_position+Vector2(0,-48))
	var barrage := formation.barrage
	for tick in 1400:
		formation.advance(1.0/240.0)
		if absf(boss._danger_flash_age-DangerFlash.PEAK_TIME)<1.0/240.0:
			press_l()
			break
	check(lan.ground_action_state==LanPlayer.GroundActionState.BACK_DODGE,"Ninth flying sword exposes a gold input peak")
	var sword_hit := CombatAttackData.new(StringName("master_rage_%d_9" % barrage.get_instance_id()),boss,24,12,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	sword_hit.evasion_key = sword_hit.attack_id
	lan.combat_timeline.seek(.3*lan.BACK_DODGE_SPEED_SCALE,true)
	check(lan.hurtbox.receive_attack(sword_hit)==CombatHitResult.Type.EVADED,"Flying-sword peak names the actual ninth blade")
	formation.queue_free()
	boss.phase = 2
	# Physical collision replay for the previously unfair first gold uppercut.
	for rate in [60,120]:
		Engine.physics_ticks_per_second = rate
		for facing in [-1.0,1.0]:
			reset(true,true,facing)
			await physics_frame
			boss.start_phase_2_body_action(&"master_phase2_rising_quake")
			var action := boss.phase_2_body_action
			var results: Array = []
			for box: CombatHitbox2D in action.hitboxes.values():
				check(box.attack.danger_type==CombatAttackData.DangerType.UNPARRYABLE_DANGER,"First real uppercut is gold")
				box.hit_resolved.connect(func(_target: Node,result: CombatHitResult.Type) -> void: results.append(int(result)))
			var pressed := false
			for tick in 90:
				boss._process(1.0/rate)
				if not pressed and absf(boss._danger_flash_age-DangerFlash.PEAK_TIME)<=.5/rate:
					press_l()
					pressed = true
				await physics_frame
				if not results.is_empty(): break
			check(pressed and results==[int(CombatHitResult.Type.EVADED)] and lan.combat_stats.health==100,"Physical peak dodge succeeds at %d Hz, facing %s" % [rate,facing])
			boss._interrupt_phase_2_action(0)
	# Brightness has one peak while approved baked art remains in use.
	boss.flash_danger(&"gold")
	var cue := boss.danger_flash
	cue.show_at(DangerFlash.PEAK_TIME,1,Vector2.ZERO)
	var peak_alpha := cue.modulate.a
	for time in [.05,.12,.17,.19,.25,.34]:
		cue.show_at(time,1,Vector2.ZERO)
		check(cue.modulate.a<peak_alpha,"Brightness is lower outside the unique peak")
	check(not cue.pieces[0]._clip.is_empty() and not cue.pieces[1]._clip.is_empty(),"Peak uses the approved baked star and shards")
	expect_save_untouched()
	finish("MASTER DODGE CUES")

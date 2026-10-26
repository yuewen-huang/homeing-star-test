extends "../tests/support/harness.gd"
## Read-only production-data audit. Run with the game project as --path.

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var boss: MasterBoss = room.get_node("MasterBoss")
	var lan: LanPlayer = room.get_node("Lan")
	boss.set_process(false)
	lan.set_physics_process(false)
	await process_frame
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	for id: StringName in MasterActionLibrary.MOVE_IDS:
		var t := boss.action_library.move(id)
		check(t.errors.is_empty(), "%s production timeline valid" % id)
		var cuts: Array = []
		for cut in t.cuts:
			cuts.append({"release": cut.release, "end": float(cut.release)+float(cut.swing), "contact": cut.contact_at})
		print("AUDIT_PHASE1 ", JSON.stringify({"id": id, "label": boss.action_library.label(id), "duration": t.duration, "cuts": cuts, "warnings": Array(t.warnings)}))
	for layer in 5:
		print("AUDIT_LAYERS ", layer, " ", boss.phase_1_ai.available(layer))
	boss._enter_phase_2()
	boss._enter_phase_2_idle(0)
	var baseline: Array = []
	for layer in 5:
		boss.charged_power = layer
		boss._finish_phase_2_howl()
		check(is_equal_approx(boss.phase_2_buff_remaining, 8.0), "Phase two buff fixed at layer %d" % layer)
		for id: StringName in MasterPhase2BodyAction.IDS:
			boss.start_phase_2_body_action(id)
			var action := boss.phase_2_body_action
			boss._process(0.05)
			check(is_equal_approx(action.elapsed, 0.07), "Phase two 1.4x at layer %d / %s" % [layer,id])
			if layer == 0:
				var at := 0.0
				var groups: Array = []
				for clip: Dictionary in action.data.clips:
					for g: Dictionary in clip.groups:
						var releases: Array = g.members.map(func(m: Dictionary) -> float: return float(m.release))
						var ends: Array = g.members.map(func(m: Dictionary) -> float: return float(m.end))
						groups.append({"clip": clip.animation, "danger": int(action._danger(clip,g)),
							"warning": at+float(g.warning)-float(clip.start_time),
							"release": at+float(releases.min())-float(clip.start_time),
							"end": at+float(ends.max())-float(clip.start_time),
							"contact": at+float(g.contact)-float(clip.start_time), "members": g.members.size()})
					at += float(clip.duration)
				print("AUDIT_PHASE2 ",JSON.stringify({"id":id,"groups":groups}))
			boss._interrupt_phase_2_action(0)
	# Success now allows a direct dodge cancel; chained parries remain available.
	lan.reset_after_map_fall(Vector2(200,555))
	lan.start_parry_success(boss.global_position)
	check(lan.can_dodge_cancel_defense(), "Successful parry accepts direct dodge cancel")
	lan.start_parry(true)
	check(lan.defense_state == LanPlayer.DefenseState.PARRY_ACTIVE, "Chained parry immediately active")
	lan.start_parry_nothing()
	check(lan.can_dodge_cancel_defense(), "Empty chained parry permits dodge cancel")
	lan.finish_defense()
	lan.start_back_dodge(-1)
	boss.action_clock.clear()
	var gold := CombatAttackData.new(&"audit_gold",boss,24,12,0,0,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	check(lan.receive_combat_hit(gold) == CombatHitResult.Type.EVADED, "Gold contact during dodge evades")
	check(is_equal_approx(lan.dodge_bullet_time_remaining,.35) and lan.is_invulnerable(), "Perfect dodge grants a short reward within its roll window")
	check(is_equal_approx(boss.get_action_time_scale(),.25), "Perfect dodge slows master to one quarter")
	boss.action_clock.clear()
	var frames := lan.animated_sprite.sprite_frames
	var success_time := 0.0
	for i in frames.get_frame_count(&"parry_success"):
		success_time += frames.get_frame_duration(&"parry_success",i)/frames.get_animation_speed(&"parry_success")
	print("AUDIT_PLAYER ",JSON.stringify({"startup":0.12,"active":0.24,"chain_active":0.34,"success_lock":success_time,"input_buffer":lan.COMBAT_INPUT_BUFFER,"boss_pause":boss.PARRY_PAUSE_DURATION}))
	# A manual red parry removes all later contacts of the current sequence.
	for id: StringName in MasterPhase2BodyAction.IDS:
		boss.phase_2_buff_remaining = 8.0
		boss.phase_2_finale_active = false
		boss.start_phase_2_body_action(id)
		var hit := CombatAttackData.new(&"audit_red",boss,18,12,0,0,CombatAttackData.DangerType.COUNTERABLE_DANGER)
		lan.start_red_parry_success(boss)
		boss.on_attack_parried(hit,lan.global_position)
		check(boss.phase_2_body_action == null and boss.red_parry_hold, "Manual red cancels sequence %s" % id)
		boss._on_red_parry_finished(boss)
	# The committed flick calls normal-hit directly, bypassing active parry and dodge.
	boss.phase = 1
	boss.manual_control = false
	for defending in ["parry", "dodge"]:
		lan.reset_after_map_fall(Vector2(200,555))
		lan.combat_stats.restore_health()
		if defending == "parry": lan.start_parry(true)
		else: lan.start_back_dodge(-1)
		var before := lan.combat_stats.health
		var flick := MasterDodgeResponse.new()
		flick.boss = boss
		flick.player = lan
		flick._land_flick()
		check(lan.combat_stats.health == before-1,"Committed flick loses 1 HP through %s" % defending)
		flick.free()
	boss._enter_phase_2()
	boss.phase_2_buff_remaining = 8
	boss.start_phase_2_body_action(MasterPhase2BodyAction.IDS[0])
	check(boss.use_sobering_item() and boss.phase_2_body_action == null, "Successful sobering removes current combo")
	# Physics replay: stand 115 world pixels away, press K at the exact action start.
	# Keep Lan's animation running; no force-active/chained parry and no aid.
	boss.manual_control = true
	for config in [{"buffed":false,"rate":60},{"buffed":true,"rate":60},{"buffed":false,"rate":120},{"buffed":true,"rate":120}]:
		var buffed: bool = config.buffed
		var rate: int = config.rate
		Engine.physics_ticks_per_second = rate
		boss.action_clock.clear()
		boss.phase_2_buff_remaining = 8.0 if buffed else 0.0
		boss.combat_stats.restore_poise()
		boss.poise_broken = false
		boss.position = Vector2(0,555)
		boss.movement_direction = 1
		lan.reset_after_map_fall(Vector2(115,555))
		lan.dodge_bullet_time_remaining = 0
		lan.evaded_action_clock.clear()
		lan.combat_stats.restore_health()
		lan.parry_chain.cancel()
		await physics_frame
		boss.start_phase_2_body_action(&"master_phase2_rising_quake")
		var observed: Array = []
		for box: CombatHitbox2D in boss.phase_2_body_action.hitboxes.values():
			box.hit_resolved.connect(func(_target: Node,result: CombatHitResult.Type) -> void: observed.append(int(result)))
		lan.start_parry()
		var ticks := 0
		while observed.is_empty() and ticks < 80:
			boss._process(1.0/rate)
			await physics_frame
			ticks += 1
		print("AUDIT_FIRST_HIT_PHYSICS ",JSON.stringify({"buffed":buffed,"physics_hz":rate,"gap":115,"ticks":ticks,"results":observed,"health":lan.combat_stats.health}))
		check(not observed.is_empty(), "First claw physically settles in replay, buffed=%s" % buffed)
		check(not observed.has(int(CombatHitResult.Type.EVADED)), "First claw replay has no invulnerability")
		boss._interrupt_phase_2_action(0)
		Engine.time_scale = 1.0
	expect_save_untouched()
	finish("MASTER TIMING AUDIT")

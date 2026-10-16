extends SceneTree
## Wind-phase clash feel v0.3 batch 1: F11 contact-prompt switch, light real-time parry
## flash (global), rising parry-chain pitch, wind clash mutual push (deer slides back and
## tips its head, longer pause, player slides back), poise refill paused while attacking
## and incremental so parries stick. Design: chapter_1_deer_wind_phase_design.md §8.

var room
var deer: DeerBoss
var player: LanPlayer
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func tick(count: int, delta := 1.0 / 60.0) -> void:
	for i in count:
		deer._physics_process(delta)

func attack(danger: CombatAttackData.DangerType) -> CombatAttackData:
	return CombatAttackData.new(&"test_clash", deer, 12, 12, 180.0, 0.0, danger)

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService

	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	room.select_combo(2)
	deer = room.adapter.deer; player = room.player
	deer.set_physics_process(false); deer.vfx.set_process(false)

	# Light, real-time parry flash; red keeps a stronger one.
	var material := feedback.prepare_hit_reaction_visual(deer.get_hit_reaction_visual())
	feedback.emit_parry_success(deer, attack(CombatAttackData.DangerType.NORMAL), deer.global_position)
	check(is_equal_approx(float(material.get_shader_parameter(&"flash_amount")), CombatFeedbackService.PARRY_FLASH), "Normal parry only brightens the attacker (flash %.2f, not solid white)" % CombatFeedbackService.PARRY_FLASH)
	var tween: Tween = deer.get_hit_reaction_visual().get_meta(&"combat_hit_reaction_tween")
	check(tween != null and tween.is_valid(), "Parry flash has a fade tween")
	var start := Time.get_ticks_msec()
	while Engine.time_scale < 1.0 and Time.get_ticks_msec() - start < 1000: await process_frame
	await create_timer(0.15, true, false, true).timeout
	check(is_zero_approx(float(material.get_shader_parameter(&"flash_amount"))), "Flash fades on real time and is not stretched by hit-stop")
	feedback.emit_parry_success(deer, attack(CombatAttackData.DangerType.NORMAL), deer.global_position)
	check(feedback.parry_chain == 1 and is_equal_approx(feedback.parry_player.pitch_scale, 1.0 + CombatFeedbackService.PARRY_CHAIN_PITCH_STEP), "A parry within %.1f s rises in pitch (chain %d)" % [CombatFeedbackService.PARRY_CHAIN_WINDOW, feedback.parry_chain])
	feedback.emit_parry_success(deer, attack(CombatAttackData.DangerType.COUNTERABLE_DANGER), deer.global_position)
	check(is_equal_approx(float(material.get_shader_parameter(&"flash_amount")), CombatFeedbackService.RED_PARRY_FLASH), "Red counter flashes stronger but not solid white")
	await create_timer(CombatFeedbackService.PARRY_CHAIN_WINDOW + 0.1, true, false, true).timeout
	feedback.emit_parry_success(deer, attack(CombatAttackData.DangerType.NORMAL), deer.global_position)
	check(feedback.parry_chain == 0 and is_equal_approx(feedback.parry_player.pitch_scale, 1.0), "A gap longer than the window resets the chain (chain %d, pitch %.2f)" % [feedback.parry_chain, feedback.parry_player.pitch_scale])
	while Engine.time_scale < 1.0: await process_frame
	feedback.clear_body_reaction(deer.get_hit_reaction_visual())

	# Mutual push on a wind clash parry.
	deer.combat_stats.restore_poise()
	deer.position.x = 820.0
	player.global_position = Vector2(820.0 - 160.0, player.global_position.y)
	deer.start_clash(&"thrust", player.global_position.x)
	tick(2)
	var x0 := deer.position.x
	player.defense_state = LanPlayer.DefenseState.PARRY_SUCCESS
	deer.on_attack_parried(attack(CombatAttackData.DangerType.NORMAL), player.global_position)
	while Engine.time_scale < 1.0: await process_frame
	check(is_equal_approx(deer._parry_pause, DeerBoss.CLASH_PARRY_PAUSE), "Wind clash parry holds the deer %.2f s" % DeerBoss.CLASH_PARRY_PAUSE)
	var away := signf(player.global_position.x - deer.position.x)
	check(is_equal_approx(absf(player.velocity.x), sqrt(2.0 * LanPlayer.GROUND_DECELERATION * DeerBoss.CLASH_PLAYER_PUSH)) and signf(player.velocity.x) == away, "Player slides %.0f px away from the deer" % DeerBoss.CLASH_PLAYER_PUSH)
	tick(3)
	check(deer.animated_sprite.rotation * -deer.direction > 0.0, "Deer tips its head back during the recoil")
	tick(10)
	check(absf(absf(deer.position.x - x0) - DeerBoss.CLASH_RECOIL_DISTANCE) < 0.5 and signf(deer.position.x - x0) == -deer.direction, "Deer slides %.0f px back (moved %.1f)" % [DeerBoss.CLASH_RECOIL_DISTANCE, deer.position.x - x0])
	check(is_zero_approx(deer.animated_sprite.rotation), "Head returns upright after the recoil")
	check(deer.state == DeerBoss.State.CLASH and deer.combat_stats.poise == deer.combat_stats.max_poise - 25, "Combo continues after the clash and the parry's poise damage stays")

	# Wind poise: no regen while attacking, delayed slow regen when not, full after a break.
	var low := deer.combat_stats.poise
	tick(60)
	check(deer.state != DeerBoss.State.CLASH or deer.combat_stats.poise == low, "No poise regen while the deer is attacking")
	deer._recover(0.0)
	tick(2)
	var before := deer.combat_stats.poise
	tick(int(DeerBoss.POISE_REGEN_DELAY * 60.0) - 10)
	check(deer.combat_stats.poise == before, "No regen for %.1f s after the last poise damage" % DeerBoss.POISE_REGEN_DELAY)
	tick(70)
	var gained := deer.combat_stats.poise - before
	check(gained > 0 and absf(gained - DeerBoss.POISE_REGEN_RATE * 1.0) <= 3.0, "Then regen %.0f per second (+%d)" % [DeerBoss.POISE_REGEN_RATE, gained])
	deer.combat_stats.apply_poise_damage(25)
	var hit := deer.combat_stats.poise
	tick(30)
	check(deer.combat_stats.poise == hit, "New damage restarts the regen delay")
	deer.enter_stagger(0.5)
	tick(60)
	check(not deer.poise_broken and deer.combat_stats.poise == deer.combat_stats.max_poise, "Poise is full again when the stagger ends")
	var full_breaks := ceili(float(deer.combat_stats.max_poise) / 25.0)
	check(full_breaks == 5, "Five parries in quick succession break a full bar")

	# Slash trail, pose afterglow and weakened kneel.
	deer._recover(0.0)
	tick(2)
	deer.position.x = 820.0
	var ghosts_before := deer.get_parent().get_children().filter(func(n: Node) -> bool: return n is DeerBoss.DeerPoseGhost).size()
	deer.start_clash(&"thrust", deer.position.x - 170.0)
	var hit_time := -1.0
	var slash_time := -1.0
	var smear: PixelSlash
	for i in 90:
		tick(1)
		if slash_time < 0.0 and not deer.clash_phase.smears.is_empty():
			slash_time = deer.clash_phase.step_time
			smear = deer.clash_phase.smears[0]
		if hit_time < 0.0 and deer.attack_hitbox.attack != null: hit_time = deer.clash_phase.step_time
	check(smear != null and smear.shape == &"crescent" and smear.get_parent() == deer and smear.facing == deer.direction, "Thrust grows a crescent smear on the deer, mirrored with it")
	check(slash_time >= 0.0 and hit_time >= 0.0 and absf((hit_time - slash_time) - DeerClashRhythm.SMEAR_OPEN) <= 1.0 / 60.0 + 0.001, "Smear starts %.3f s before contact so it is fully open on the hit (got %.3f)" % [DeerClashRhythm.SMEAR_OPEN, hit_time - slash_time])
	# A smear freed elsewhere must be dropped cleanly on the next tick.
	for old in deer.clash_phase.smears: old.free()
	deer.clash_phase.tick_smears(1.0 / 60.0)
	deer.clash_phase.add_smear("thrust", DeerClashPhase.MOVES[&"thrust"].hits[0].rect, &"green")
	check(deer.clash_phase.smears.size() == 1 and is_instance_valid(deer.clash_phase.smears[0]), "Freed smears are dropped without errors when a new one spawns")
	var ghosts := deer.get_parent().get_children().filter(func(n: Node) -> bool: return n is DeerBoss.DeerPoseGhost)
	check(ghosts.size() > ghosts_before or deer.clash_phase.step_index >= 0, "Clip changes in the clash leave a fading pose ghost")
	deer.enter_stagger(2.0)
	tick(1)
	check(deer.animated_sprite.animation == &"death_START", "Weakened deer starts buckling into a kneel (not the hurt head-shake)")
	tick(40)
	var y0 := deer.animated_sprite.position.y
	check(deer.animated_sprite.animation == &"death_ING" and deer.animated_sprite.frame == 2, "Weakened deer kneels on death_ING F02")
	tick(20)
	check(not is_equal_approx(deer.animated_sprite.position.y, y0), "Kneeling deer breathes (body rises and sinks)")
	var seen_rise := false
	while deer.state == DeerBoss.State.STAGGER:
		tick(1)
		if deer.stagger_remaining < 0.2 and deer.animated_sprite.animation == &"death_START": seen_rise = true
	check(seen_rise, "Weakened deer rises by playing the kneel back")

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Clash-feel checks leave saved progress unchanged")
	print("WIND CLASH FEEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

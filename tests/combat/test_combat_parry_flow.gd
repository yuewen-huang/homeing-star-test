extends SceneTree


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func make_attack(source: Node2D, id: StringName = &"test") -> CombatAttackData:
	return CombatAttackData.new(
		id, source, 20, 12, 320.0, -310.0,
		CombatAttackData.DangerType.NORMAL
	)


func spawn_player(room: Node2D, name_suffix: String) -> LanPlayer:
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	player.name = "Lan%s" % name_suffix
	player.world_min_x = -1000.0
	player.world_max_x = 1000.0
	room.add_child(player)
	return player


func run_test() -> void:
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var room := Node2D.new()
	root.add_child(room)
	current_scene = room
	var camera := Camera2D.new()
	camera.enabled = true
	room.add_child(camera)
	var source := DamageReceiver2D.new()
	source.position = Vector2(100.0, 0.0)
	room.add_child(source)

	var timing_player := spawn_player(room, "Timing")
	await process_frame
	var frames := timing_player.animated_sprite.sprite_frames
	var parry_duration := 0.0
	for frame_index in frames.get_frame_count(&"parry"):
		parry_duration += frames.get_frame_duration(&"parry", frame_index) / frames.get_animation_speed(&"parry")
	if not require(is_equal_approx(parry_duration, 0.36), "Parry must preserve three 40ms startup frames and two 120ms active frames"):
		return
	if not require(frames.get_frame_count(&"parry_nothing") == 5, "Parry nothing phase must contain five 70ms frames"):
		return
	var nothing_first := frames.get_frame_texture(&"parry_nothing", 0) as AtlasTexture
	var nothing_last := frames.get_frame_texture(&"parry_nothing", 4) as AtlasTexture
	if not require(
		nothing_first != null
		and nothing_last != null
		and nothing_first.atlas.resource_path.ends_with("parry_nothing_160x160_5f.png")
		and nothing_first.region != nothing_last.region,
		"Parry nothing does not use its dedicated five-frame sheet",
	):
		return

	var startup_player := spawn_player(room, "Startup")
	await process_frame
	startup_player.start_parry()
	var startup_health := startup_player.combat_stats.health
	var startup_result := startup_player.receive_combat_hit(make_attack(source, &"startup"))
	if not require(startup_result == CombatHitResult.Type.NORMAL_HIT, "Startup contact was not a normal hit"):
		return
	if not require(startup_player.combat_stats.health == startup_health - 20 and startup_player.hit_reaction_active, "Startup contact did not deal full damage and launch"):
		return

	var active_player := spawn_player(room, "Active")
	await process_frame
	active_player.start_parry()
	active_player.animated_sprite.frame = 3
	active_player.on_player_animation_frame_changed()
	active_player.parry_input_buffer_remaining = active_player.COMBAT_INPUT_BUFFER
	var active_health := active_player.combat_stats.health
	var active_result := active_player.receive_combat_hit(make_attack(source, &"active"))
	# The hitbox reports a successful defense back to the attacker; the receiver
	# owns shared contact feedback now, rather than Lan's state transition.
	source.on_attack_parried(make_attack(source, &"active_feedback"), active_player.defense_contact_point(source.global_position))
	if not require(active_result == CombatHitResult.Type.PARRY_SUCCESS, "Active contact did not parry"):
		return
	if not require(active_player.combat_stats.health == active_health and active_player.defense_state == active_player.DefenseState.PARRY_SUCCESS, "Successful parry changed health or skipped its animation"):
		return
	if not require(active_player.defense_recoil_active and active_player.velocity.x < 0.0 and not active_player.hit_reaction_active, "Successful parry did not apply its light defensive recoil"):
		return
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	if not require(feedback.shake_remaining >= CombatFeedbackService.SHAKE_DURATION, "Successful parry did not request shared clash screen shake"):
		return
	if not require(feedback.shake_target == camera, "Successful parry shake was not applied to the active camera"):
		return
	if not require(active_player.parry_input_buffer_remaining == 0.0 and active_player.animated_sprite.animation == &"parry_success", "The triggering parry input immediately overwrote the success animation"):
		return
	active_player.start_parry()
	if not require(active_player.defense_state == active_player.DefenseState.PARRY_STARTUP, "Success animation could not restart parry"):
		return

	var early_player := spawn_player(room, "EarlyNothing")
	await process_frame
	early_player.start_parry_nothing()
	var early_health := early_player.combat_stats.health
	var early_result := early_player.receive_combat_hit(make_attack(source, &"early_nothing"))
	if not require(early_result == CombatHitResult.Type.PARRY_FAILURE, "Early nothing contact did not trigger parry failure"):
		return
	if not require(early_player.combat_stats.health == early_health - 10 and early_player.defense_state == early_player.DefenseState.PARRY_FAILURE, "Parry failure did not apply half damage"):
		return
	if not require(early_player.defense_recoil_active and early_player.velocity.x < -active_player.PARRY_SUCCESS_RECOIL_SPEED and not early_player.hit_reaction_active and not early_player.ground_knockback_active, "Parry failure did not use its stronger, defense-only recoil"):
		return
	if not require(early_player.can_dodge_cancel_defense(), "Parry failure cannot be dodge-cancelled"):
		return

	var late_player := spawn_player(room, "LateNothing")
	await process_frame
	late_player.start_parry_nothing()
	late_player.animated_sprite.frame = 2
	late_player.on_player_animation_frame_changed()
	var late_health := late_player.combat_stats.health
	var late_result := late_player.receive_combat_hit(make_attack(source, &"late_nothing"))
	if not require(late_result == CombatHitResult.Type.NORMAL_HIT, "Late nothing contact was not a normal hit"):
		return
	if not require(late_player.combat_stats.health == late_health - 20 and late_player.hit_reaction_active, "Late nothing contact did not deal full damage and launch"):
		return

	var cancel_player := spawn_player(room, "Cancel")
	await process_frame
	cancel_player.attack_state = cancel_player.AttackState.ATTACK_3X
	cancel_player.animated_sprite.play(&"attack_3x")
	cancel_player.parry_input_buffer_remaining = cancel_player.COMBAT_INPUT_BUFFER
	if not require(cancel_player.can_interrupt_ground_action_with_parry(), "Ground attack cannot be cancelled into parry"):
		return
	cancel_player.consume_buffered_parry()
	cancel_player.interrupt_ground_action_with_parry()
	if not require(cancel_player.attack_state == cancel_player.AttackState.NONE and cancel_player.defense_state == cancel_player.DefenseState.PARRY_STARTUP, "Parry did not take priority over a ground attack"):
		return
	cancel_player.start_parry_nothing()
	if not require(not cancel_player.can_interrupt_ground_action_with_parry(), "Nothing phase incorrectly allowed parry to cancel itself"):
		return
	cancel_player.start_parry_failure()
	if not require(not cancel_player.can_interrupt_ground_action_with_parry(), "Failure animation incorrectly allowed parry to cancel itself"):
		return

	var damage_only_player := spawn_player(room, "DamageOnly")
	await process_frame
	damage_only_player.start_attack_1x()
	var damage_only_health := damage_only_player.combat_stats.health
	var damage_only_attack := CombatAttackData.new(
		&"damage_only", source, 20, 0, 0.0, 0.0,
		CombatAttackData.DangerType.NORMAL
	)
	damage_only_player.receive_combat_hit(damage_only_attack)
	if not require(damage_only_player.combat_stats.health == damage_only_health - 20, "Damage-only hit did not deal damage"):
		return
	if not require(damage_only_player.attack_state == damage_only_player.AttackState.ATTACK_1X and not damage_only_player.hit_reaction_active, "Damage-only hit interrupted Lan's current action"):
		return

	var knockback_player := spawn_player(room, "GroundKnockback")
	await process_frame
	var knockback_attack := CombatAttackData.new(
		&"ground_knockback", source, 20, 0, 320.0, 0.0,
		CombatAttackData.DangerType.NORMAL
	)
	knockback_player.receive_combat_hit(knockback_attack)
	if not require(knockback_player.ground_knockback_active and knockback_player.hit_reaction_active, "Ground knockback did not enter its restricted recovery"):
		return
	knockback_player.parry_input_buffer_remaining = knockback_player.COMBAT_INPUT_BUFFER
	knockback_player._physics_process(0.0)
	if not require(not knockback_player.hit_reaction_active and knockback_player.defense_state == knockback_player.DefenseState.PARRY_STARTUP, "Parry could not cancel ground knockback"):
		return

	var launch_player := spawn_player(room, "Launch")
	await process_frame
	launch_player.receive_combat_hit(make_attack(source, &"launch"))
	launch_player.parry_input_buffer_remaining = launch_player.COMBAT_INPUT_BUFFER
	launch_player._physics_process(0.0)
	if not require(launch_player.hit_reaction_active and not launch_player.ground_knockback_active and launch_player.defense_state == launch_player.DefenseState.NONE, "Launch incorrectly allowed a defensive cancel"):
		return

	var assisted_roll_player := spawn_player(room, "AssistedRoll")
	await process_frame
	if not require(assisted_roll_player.can_accept_parry_action() == assisted_roll_player.can_start_parry(), "Idle chain-parry eligibility differs from manual K"):
		return
	for blocked_air_state in [
		assisted_roll_player.AirState.LANDING,
		assisted_roll_player.AirState.ROLL_LANDING,
		assisted_roll_player.AirState.RISING,
		assisted_roll_player.AirState.DOUBLE_JUMPING,
		assisted_roll_player.AirState.FALLING,
		assisted_roll_player.AirState.WALL_SLIDING,
	]:
		assisted_roll_player.air_state = blocked_air_state
		if not require(not assisted_roll_player.can_accept_parry_action(), "A state that rejects manual K allowed an assisted parry"):
			return
	assisted_roll_player.air_state = assisted_roll_player.AirState.GROUNDED
	assisted_roll_player.attack_state = assisted_roll_player.AttackState.DODGE_ATTACK_2X
	if not require(not assisted_roll_player.can_accept_parry_action(), "Dodge attack 2 startup incorrectly allowed an assisted parry"):
		return
	assisted_roll_player.attack_state = assisted_roll_player.AttackState.NONE
	assisted_roll_player.start_attack_1x()
	if not require(assisted_roll_player.can_accept_parry_action() == assisted_roll_player.can_interrupt_ground_action_with_parry(), "Ground attack chain-parry eligibility differs from manual K interrupt"):
		return
	assisted_roll_player.finish_ground_attack()
	assisted_roll_player.start_roll_landing(1.0)
	assisted_roll_player.animated_sprite.frame = 4
	var assisted_result := assisted_roll_player.resolve_chain_parry(make_attack(source, &"assisted_roll"))
	if not require(assisted_result == CombatHitResult.Type.PARRY_SUCCESS, "Assisted parry did not resolve from roll landing"):
		return
	if not require(
		assisted_roll_player.air_state == assisted_roll_player.AirState.GROUNDED
		and assisted_roll_player.ground_action_state == assisted_roll_player.GroundActionState.NONE
		and assisted_roll_player.defense_state == assisted_roll_player.DefenseState.PARRY_SUCCESS,
		"Assisted parry did not fully exit the interrupted roll landing",
	):
		return
	assisted_roll_player.finish_defense()
	if not require(assisted_roll_player.can_start_ground_attack() and assisted_roll_player.can_start_parry(), "Assisted parry recovery left ground actions locked"):
		return
	assisted_roll_player.start_attack_1x()
	if not require(assisted_roll_player.attack_state == assisted_roll_player.AttackState.ATTACK_1X, "Attack did not recover after assisted parry"):
		return
	assisted_roll_player.finish_ground_attack()
	assisted_roll_player.start_back_dodge()
	if not require(assisted_roll_player.ground_action_state == assisted_roll_player.GroundActionState.BACK_DODGE, "Dodge did not recover after assisted parry"):
		return
	var assisted_landing_player := spawn_player(room, "AssistedLanding")
	await process_frame
	assisted_landing_player.air_state = assisted_landing_player.AirState.LANDING
	assisted_landing_player.animated_sprite.play(&"land")
	assisted_landing_player.resolve_chain_parry(make_attack(source, &"assisted_landing"))
	assisted_landing_player.finish_defense()
	if not require(
		assisted_landing_player.air_state == assisted_landing_player.AirState.GROUNDED
		and assisted_landing_player.can_start_ground_attack()
		and assisted_landing_player.can_start_parry(),
		"Assisted parry did not recover from the normal landing state",
	):
		return

	var chain_player := spawn_player(room, "ChainGrace")
	await process_frame
	chain_player.start_parry(true)
	if not require(chain_player.defense_state == chain_player.DefenseState.PARRY_ACTIVE and chain_player.animated_sprite.frame == chain_player.PARRY_STARTUP_FRAME_COUNT, "Chained parry did not skip startup and begin on its first active frame"):
		return
	chain_player.animated_sprite.set_frame_and_progress(4, 1.0)
	chain_player.on_animation_finished()
	if not require(chain_player.defense_state == chain_player.DefenseState.PARRY_ACTIVE and is_equal_approx(chain_player.parry_active_extension_remaining, 0.10), "Chained parry did not retain the 100ms active grace"):
		return
	chain_player.update_defense_timing(0.10)
	if not require(chain_player.defense_state == chain_player.DefenseState.PARRY_NOTHING_EARLY, "Chained parry grace did not end in the nothing phase"):
		return

	print("PASS: parry timing, reaction types, assisted roll recovery, chained grace, and cancels")
	quit(0)

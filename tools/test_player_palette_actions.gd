extends SceneTree


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func run_test() -> void:
	seed(1)
	var player = (load("res://scenes/sideview/lan_player.tscn") as PackedScene).instantiate()
	player.set("world_min_x", -10000.0)
	player.set("world_max_x", 10000.0)
	root.add_child(player)
	await process_frame

	var expected := {
		&"attack_1x": 16, &"attack_2x": 25, &"attack_2x_1": 6,
		&"attack_2x_2": 10, &"attack_3x": 30,
		&"jump_attack_1x": 9, &"jump_attack_2x": 8,
		&"dodge_attack_1x": 19, &"dodge_attack_2x": 16,
		&"dodge_attack_3x_z": 37, &"dodge_attack_3x_z1": 37,
	}
	for animation_name in expected:
		if not require(player.animated_sprite.sprite_frames.has_animation(animation_name), "Missing animation %s" % animation_name):
			return
		if not require(player.animated_sprite.sprite_frames.get_frame_count(animation_name) == expected[animation_name], "Wrong frame count for %s" % animation_name):
			return
	if not require(
		player.combat_stats.max_stamina == 100.0
		and player.combat_stats.stamina == 100.0
		and player.combat_stats.max_mana == 100.0
		and player.combat_stats.mana == 0.0,
		"Lan resource pools did not initialize correctly"
	):
		return
	if not require(player.has_node("PlayerStatusHUD") and player.has_node("SkillBar"), "Lan combat HUD is incomplete"):
		return
	if not require(InputMap.has_action(&"instant_dash"), "Instant dash input action is missing"):
		return

	var second_attack_states := {}
	for attempt in 30:
		player.attack_state = player.AttackState.NONE
		player.air_state = player.AirState.GROUNDED
		player.start_attack_1x()
		player.attack_queued = true
		player.on_combat_timeline_finished(&"attack_1x")
		second_attack_states[player.attack_state] = true
		if not require(player.attack_state in [player.AttackState.ATTACK_2X, player.AttackState.ATTACK_2X_1, player.AttackState.ATTACK_2X_2], "Ground combo selected an invalid second attack"):
			return
		player.attack_queued = true
		player.on_combat_timeline_finished(player.animated_sprite.animation)
		if not require(player.attack_state == player.AttackState.ATTACK_3X, "Ground combo did not finish with attack 3x"):
			return
		player.on_combat_timeline_finished(&"attack_3x")
	if not require(second_attack_states.size() == 3, "Random second attack did not exercise all three variants"):
		return

	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.GROUNDED
	player.start_attack_1x(-1.0)
	player.queued_attack_direction = 1.0
	player.attack_queued = true
	player.on_combat_timeline_finished(&"attack_1x")
	if not require(is_equal_approx(player.facing_direction, 1.0), "Ground combo did not apply the buffered direction on attack 2x"):
		return
	player.queued_attack_direction = -1.0
	player.attack_queued = true
	player.on_combat_timeline_finished(player.animated_sprite.animation)
	if not require(player.attack_state == player.AttackState.ATTACK_3X and is_equal_approx(player.facing_direction, -1.0), "Ground combo did not apply the buffered direction on attack 3x"):
		return

	player.attack_state = player.AttackState.JUMP_ATTACK_1X
	player.air_state = player.AirState.RISING
	player.facing_direction = -1.0
	player.input_direction = 1.0
	player.update_air_facing()
	if not require(is_equal_approx(player.facing_direction, -1.0), "Air attack changed facing before its segment ended"):
		return

	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.RISING
	player.start_jump_attack_1x()
	player.attack_queued = true
	player.on_animation_finished()
	if not require(player.attack_state == player.AttackState.JUMP_ATTACK_2X, "Jump combo did not advance to attack 2x"):
		return

	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.GROUNDED
	player.start_back_dodge()
	player.start_dodge_attack_1x()
	player.attack_queued = true
	player.on_combat_timeline_finished(&"dodge_attack_1x")
	if not require(player.attack_state == player.AttackState.DODGE_ATTACK_2X, "Dodge combo did not advance to attack 2x"):
		return
	player.attack_queued = true
	player.on_combat_timeline_finished(&"dodge_attack_2x")
	if not require(player.attack_state == player.AttackState.DODGE_ATTACK_3X, "Dodge combo did not advance to attack 3x"):
		return
	if not require(player.air_state == player.AirState.GROUNDED and player.velocity == Vector2.ZERO, "Dodge attack 3x did not begin with a grounded charge"):
		return
	if not require(player.animated_sprite.animation in [&"dodge_attack_3x_z", &"dodge_attack_3x_z1"] and player.animated_sprite.frame == 0, "Dodge attack 3x did not select a complete character variant"):
		return
	player.update_dodge_attack_3_phase()
	if not require(not player.dodge_attack_3_teleported and is_equal_approx(player.global_position.y, player.ground_y), "Dodge attack 3x left the ground before its charge completed"):
		return
	player._timeline_dodge_attack_3_teleport()
	if not require(player.air_state == player.AirState.FALLING and player.velocity == Vector2(0.0, player.DODGE_ATTACK_3_DROP_SPEED), "Dodge attack 3x did not begin its timed drop after teleporting"):
		return
	if not require(is_equal_approx(player.global_position.y, player.ground_y - player.DODGE_ATTACK_3_DROP_HEIGHT), "Dodge attack 3x did not teleport to the configured height"):
		return
	var attack_last_frame_bottom: float = -43.0 \
		+ (player.DODGE_ATTACK_3_SPRITE_OFFSET_Y \
		+ 206.0 - player.DODGE_ATTACK_3_FRAME_SIZE.y * 0.5) * 1.5
	var idle_frame_bottom: float = -43.0 + (55.0 - 55.0 * 0.5) * 1.5
	if not require(is_equal_approx(attack_last_frame_bottom, idle_frame_bottom), "Dodge attack 3x recovery baseline does not match idle"):
		return
	var drop_ticks := 0
	while player.air_state == player.AirState.FALLING and drop_ticks < 60:
		player._physics_process(1.0 / 60.0)
		drop_ticks += 1
	if not require(
		player.air_state == player.AirState.GROUNDED and drop_ticks < 60,
		"Dodge attack 3x did not land: ticks=%d state=%d y=%.2f" % [
			drop_ticks, player.air_state, player.position.y,
		],
	):
		return
	var dodge_3_effect := LanAttackEffectCatalog.dodge_attack_3x(player.DODGE_ATTACK_3_SPRITE_POSITION_Y)
	if not require(dodge_3_effect.frame_count == 37, "Dodge attack 3x primary effect is not timeline-aligned"):
		return
	var dodge_3_secondary_effect := LanAttackEffectCatalog.dodge_attack_3x_secondary(player.DODGE_ATTACK_3_SPRITE_POSITION_Y)
	if not require(dodge_3_secondary_effect.frame_count == 37, "Dodge attack 3x secondary effect is not timeline-aligned"):
		return
	var added_effects := [
		LanAttackEffectCatalog.attack_3x(player.ATTACK_3_FPS),
		LanAttackEffectCatalog.dodge_attack_1x(player.DODGE_ATTACK_1_FPS),
		LanAttackEffectCatalog.dodge_attack_2x(player.DODGE_ATTACK_2_FPS),
		LanAttackEffectCatalog.jump_attack_1x(player.JUMP_ATTACK_1X_FPS),
		LanAttackEffectCatalog.jump_attack_2x(player.JUMP_ATTACK_2X_FPS),
	]
	for effect_config in added_effects:
		if not require(effect_config.texture != null and not effect_config.hitboxes.is_empty(), "A newly connected attack effect is incomplete"):
			return

	player.attack_state = player.AttackState.ATTACK_3X
	player.air_state = player.AirState.GROUNDED
	player.animated_sprite.play(&"attack_3x")
	player.animated_sprite.frame = 0
	player.dodge_input_buffer_remaining = player.COMBAT_INPUT_BUFFER
	player.dodge_buffer_direction = 1.0
	if not require(player.can_interrupt_ground_action_with_dodge(), "Attack 3x could not be interrupted by the high-priority dodge"):
		return
	player.consume_buffered_dodge()
	player.interrupt_ground_action_with_dodge()
	if not require(player.ground_action_state == player.GroundActionState.BACK_DODGE and player.attack_state == player.AttackState.NONE, "Ground attack interrupt did not enter back dodge"):
		return
	if not require(is_equal_approx(player.get_action_movement_direction(), 1.0), "Directional dodge did not preserve its requested movement direction"):
		return
	player._timeline_set_back_dodge_invulnerable(true)
	if not require(player.is_invulnerable() and not player.can_receive_hit(), "Dodge invulnerability window was not active"):
		return

	player.attack_input_buffer_remaining = player.COMBAT_INPUT_BUFFER
	if not require(player.has_buffered_attack(), "Attack input buffer was not retained through back dodge"):
		return
	player.consume_buffered_attack()
	player.start_dodge_attack_1x()
	if not require(player.attack_state == player.AttackState.DODGE_ATTACK_1X, "Buffered attack did not branch from back dodge into dodge attack 1x"):
		return

	player.combat_stats.stamina = player.combat_stats.max_stamina
	player.attack_state = player.AttackState.NONE
	player.ground_action_state = player.GroundActionState.NONE
	player.air_state = player.AirState.GROUNDED
	player.start_instant_dash()
	if not require(
		player.instant_dash_cooldown_remaining == player.INSTANT_DASH_COOLDOWN,
		"Instant dash did not begin its cooldown"
	):
		return
	player.update_player_resources(player.INSTANT_DASH_COOLDOWN)
	if not require(is_zero_approx(player.instant_dash_cooldown_remaining), "Instant dash cooldown did not finish"):
		return
	player.combat_stats.stamina = 40.0
	player.update_player_resources(1.0)
	if not require(is_equal_approx(player.combat_stats.stamina, 56.0), "Stamina did not recover at its configured rate"):
		return
	player._on_attack_effect_hit_landed(null)
	if not require(is_equal_approx(player.combat_stats.mana, player.MANA_GAIN_PER_HIT), "Attack hits did not generate mana"):
		return

	print("PASS: attacks, resources, cooldowns, HUD, hitboxes, and input buffers all load")
	quit(0)

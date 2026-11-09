extends "../../support/harness.gd"
var player: LanPlayer
var progress: MemoryProgress

func tick(frames := 1) -> void:
	for i in frames: player._physics_process(1.0 / 60.0)

func press_i() -> void:
	Input.action_press(&"special_attack")
	tick()

func release_i() -> void:
	Input.action_release(&"special_attack")
	tick()

func reset() -> void:
	Input.action_release(&"special_attack")
	Input.action_release(&"parry")
	player.set_input_frozen(false)
	player.set_boss_controlled(false)
	player.cancel_uncommitted_attack_effects()
	player.consume_buffered_special_attack()
	player.attack_state = LanPlayer.AttackState.NONE
	player.ground_action_state = LanPlayer.GroundActionState.NONE
	player.defense_state = LanPlayer.DefenseState.NONE
	player.hit_reaction_active = false
	player.ground_knockback_active = false
	player.air_state = LanPlayer.AirState.GROUNDED
	player.velocity = Vector2.ZERO
	player.position = Vector2(0, 555)
	player.combat_stats.restore_health()
	player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
	player.play_idle()
	player.resync_held_input_state()
	tick()

func wait_for_wave_end() -> void:
	for i in 90:
		if player.attack_state != LanPlayer.AttackState.SWORD_WAVE:
			return
		await process_frame

func run() -> void:
	progress = use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var was_invincible := assist.player_invincible
	assist.set_player_invincible(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	player = load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.position = Vector2(0, 555)
	player.world_min_x = -1800.0
	player.world_max_x = 1800.0
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame

	var events := InputMap.action_get_events(&"special_attack")
	check(events.any(func(e) -> bool: return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_I), "I is the sword-wave input")
	var frames := player.animated_sprite.sprite_frames
	check(frames.get_frame_count(&"sword_wave") == 24 and not frames.get_animation_loop(&"sword_wave"), "All 24 native frames play once")
	var native := is_equal_approx(frames.get_animation_speed(&"sword_wave"), 10.0)
	for frame in frames.get_frame_count(&"sword_wave"): native = native and is_equal_approx(frames.get_frame_duration(&"sword_wave", frame), 1.0)
	check(native, "Native 100ms frame duration is preserved")

	reset()
	player.facing_direction = -1.0
	player.apply_facing_direction()
	player.combat_stats.add_mana(40.0)
	var mana := player.combat_stats.mana
	var stamina := player.combat_stats.stamina
	var stamina_per_tick := LanPlayer.STAMINA_RECOVERY_PER_SECOND / 60.0
	press_i()
	check(player.attack_state == LanPlayer.AttackState.SWORD_WAVE and player.animated_sprite.animation == &"sword_wave", "Grounded I enters sword wave")
	check(player.animated_sprite.offset == Vector2(-LanPlayer.SWORD_WAVE_SPRITE_OFFSET_X, -2.0) and not player.animated_sprite.flip_h, "Left-facing body uses the authored opening pivot")
	check(player.sword_wave_charging and not player.animated_sprite.is_playing(), "I holds the sword-wave windup")
	tick(41)
	check(player.sword_wave_charge_elapsed < LanPlayer.SWORD_WAVE_CHARGE_TIME, "41 frames do not reach full charge at 60 Hz")
	tick()
	check(is_equal_approx(player.sword_wave_charge_elapsed, 0.9 / 1.3), "Full charge takes 42 frames at 60 Hz")
	check(player.sword_wave_charging and player.sword_wave_fx.projectiles.is_empty(), "Full charge waits for release without firing")
	release_i()
	check(not player.sword_wave_charging and player.combat_stats.stamina == stamina, "Releasing I begins the attack without spending before the first wave")
	check(is_equal_approx(player.animated_sprite.speed_scale, 1.5 * 1.45), "Fully charged release plays 50 percent faster than the original")
	var spends: Array[float] = []
	var record_spend := func(current: float, _maximum: float) -> void: spends.append(current)
	player.combat_stats.stamina_changed.connect(record_spend)
	await wait_for_wave_end()
	player.combat_stats.stamina_changed.disconnect(record_spend)
	check(player.attack_state == LanPlayer.AttackState.NONE and player.animated_sprite.animation == &"idle", "Natural animation completion restores idle")
	check(spends == [stamina - 20.0, stamina - 40.0, stamina - 60.0], "Three animation-driven emissions each spend exactly 20 stamina")
	check(player.combat_stats.mana == mana, "Emitting sword waves does not spend mana")
	press_i()
	check(player.sword_wave_charging, "A new I can charge immediately after animation recovery")
	release_i()
	player.cancel_uncommitted_attack_effects()
	player.finish_ground_attack()
	tick(20)
	check(player.attack_state == LanPlayer.AttackState.NONE, "An interrupted release returns to idle")
	release_i()

	reset()
	player.combat_stats.consume_stamina(player.combat_stats.stamina - 30.0)
	press_i()
	release_i()
	await wait_for_wave_end()
	var bar := player.get_node("SkillBar")
	var icon: TextureRect = bar.skill_icons[&"special_attack"]
	check(is_equal_approx(player.combat_stats.stamina, 10.0 + 2.0 * stamina_per_tick) and icon.modulate == bar.LOCKED_COLOR,
		"Thirty stamina buys one emission and the slot dims when stamina runs low")
	press_i()
	check(not player.sword_wave_charging and player.attack_state == LanPlayer.AttackState.NONE, "I with less than 20 stamina does not start an attack")
	release_i()
	player.combat_stats.restore_stamina(10.0)
	check(icon.modulate == bar.AVAILABLE_COLOR, "Recovering enough stamina restores the icon")

	reset()
	Input.action_press(&"ui_right")
	press_i()
	Input.action_release(&"ui_right")
	check(player.facing_direction > 0.0 and player.animated_sprite.offset == Vector2(LanPlayer.SWORD_WAVE_SPRITE_OFFSET_X, -2.0) and player.animated_sprite.flip_h, "Right-facing body mirrors around the same pivot")
	release_i()
	for i in 30:
		if player.combat_stats.stamina < stamina:
			break
		await process_frame
	check(player.combat_stats.stamina == stamina - 20.0, "Only the first emission has fired before parry")

	Input.action_press(&"parry")
	tick()
	Input.action_release(&"parry")
	await process_frame
	check(player.attack_state == LanPlayer.AttackState.NONE and player.defense_state != LanPlayer.DefenseState.NONE, "K cancels sword wave into parry")
	await wait_frames(60)
	check(is_equal_approx(player.combat_stats.stamina, stamina - 20.0 + stamina_per_tick),
		"K after the first wave prevents all subsequent stamina charges")
	reset()
	press_i()
	check(player.attack_state == LanPlayer.AttackState.SWORD_WAVE, "A fresh I starts normally after parry recovery")
	release_i()

	var dodge := InputEventKey.new()
	dodge.physical_keycode = KEY_L
	dodge.pressed = true
	Input.parse_input_event(dodge)
	Input.flush_buffered_events()
	tick()
	var dodge_up := dodge.duplicate() as InputEventKey
	dodge_up.pressed = false
	Input.parse_input_event(dodge_up)
	Input.flush_buffered_events()
	check(player.attack_state == LanPlayer.AttackState.NONE and player.ground_action_state != LanPlayer.GroundActionState.NONE, "Dodge cancels sword wave")

	reset()
	press_i()
	player.set_input_frozen(true)
	check(player.attack_state == LanPlayer.AttackState.NONE and player.animated_sprite.offset == Vector2.ZERO, "Dialogue freeze clears the move and sprite offset")
	player.set_input_frozen(false)
	tick(3)
	check(player.attack_state == LanPlayer.AttackState.NONE, "Held I does not fire after dialogue closes")
	release_i()

	reset()
	press_i()
	player.set_boss_controlled(true)
	check(player.attack_state == LanPlayer.AttackState.NONE and player.animated_sprite.offset == Vector2.ZERO, "Boss control clears sword-wave state")
	player.set_boss_controlled(false)
	release_i()

	reset()
	press_i()
	var dummy := Node2D.new()
	world.add_child(dummy)
	dummy.position = Vector2(200, 555)
	var hit := player.receive_combat_hit(CombatAttackData.new(&"sword_wave_test_hit", dummy, 5, 5, 180.0, 0.0))
	check(hit == CombatHitResult.Type.NORMAL_HIT and player.hit_reaction_active and player.attack_state == LanPlayer.AttackState.NONE, "A hit interrupts sword wave normally")
	dummy.free()
	release_i()
	check(player.combat_stats.stamina == stamina, "A hit before the first emission spends no stamina")

	reset()
	press_i()
	release_i()
	for i in 50:
		if player.combat_stats.stamina <= stamina - 40.0:
			break
		await process_frame
	check(player.combat_stats.stamina == stamina - 40.0, "Exactly two emissions have fired before the incoming hit")
	dummy = Node2D.new()
	world.add_child(dummy)
	dummy.position = Vector2(200, 555)
	hit = player.receive_combat_hit(CombatAttackData.new(&"sword_wave_test_hit", dummy, 5, 5, 180.0, 0.0))
	check(hit == CombatHitResult.Type.NORMAL_HIT and player.attack_state == LanPlayer.AttackState.NONE, "A hit cancels the third emission")
	await wait_frames(60)
	check(player.combat_stats.stamina == stamina - 40.0, "Taking a hit after two emissions does not charge the third")
	dummy.free()

	reset()
	press_i()
	player.air_state = LanPlayer.AirState.FALLING
	tick()
	check(player.attack_state == LanPlayer.AttackState.NONE, "Losing ground support cannot leave sword wave stuck")
	release_i()

	reset()
	player.air_state = LanPlayer.AirState.FALLING
	press_i()
	check(player.attack_state != LanPlayer.AttackState.SWORD_WAVE, "I does not start the grounded move while airborne")
	release_i()

	reset()
	progress.locked.append(SaveProgressService.ABILITY_ATTACK)
	press_i()
	check(player.attack_state != LanPlayer.AttackState.SWORD_WAVE, "Existing prologue attack lock also blocks I")
	release_i()
	progress.locked.clear()

	expect_save_untouched()
	current_scene = null
	world.free()
	assist.set_player_invincible(was_invincible)
	finish("SWORD WAVE")

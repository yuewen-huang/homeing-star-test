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
	player.sword_wave_cooldown_remaining = 0.0
	player.position = Vector2(0, 555)
	player.combat_stats.restore_health()
	player.play_idle()
	player.resync_held_input_state()
	tick()

func finish_animation() -> void:
	var sprite := player.animated_sprite
	sprite.frame = sprite.sprite_frames.get_frame_count(&"sword_wave") - 1
	player.on_animation_finished()

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
	var mana := player.combat_stats.mana
	var stamina: float = player.combat_stats.stamina if "stamina" in player.combat_stats else 0.0
	press_i()
	check(player.attack_state == LanPlayer.AttackState.SWORD_WAVE and player.animated_sprite.animation == &"sword_wave", "Grounded I enters sword wave")
	check(player.animated_sprite.offset == Vector2(-LanPlayer.SWORD_WAVE_SPRITE_OFFSET_X, -2.0) and not player.animated_sprite.flip_h, "Left-facing body uses the authored opening pivot")
	check(player.sword_wave_charging and not player.animated_sprite.is_playing(), "I holds the sword-wave windup")
	tick(70)
	check(player.sword_wave_charging and player.sword_wave_fx.projectiles.is_empty(), "Full charge waits for release without firing")
	release_i()
	check(not player.sword_wave_charging and player.sword_wave_cooldown_remaining > 0.0, "Release commits the wave and starts cooldown")
	finish_animation()
	check(player.attack_state == LanPlayer.AttackState.NONE and player.animated_sprite.animation == &"idle", "Natural animation completion restores idle")
	tick(20)
	check(player.attack_state == LanPlayer.AttackState.NONE, "Holding I does not repeat the move")
	var stamina_after: float = player.combat_stats.stamina if "stamina" in player.combat_stats else 0.0
	check(is_equal_approx(player.combat_stats.mana, mana) and is_equal_approx(stamina_after, stamina), "Sword wave has no resource cost")
	release_i()

	reset()
	Input.action_press(&"ui_right")
	press_i()
	Input.action_release(&"ui_right")
	check(player.facing_direction > 0.0 and player.animated_sprite.offset == Vector2(LanPlayer.SWORD_WAVE_SPRITE_OFFSET_X, -2.0) and player.animated_sprite.flip_h, "Right-facing body mirrors around the same pivot")
	release_i()

	Input.action_press(&"parry")
	tick()
	Input.action_release(&"parry")
	await process_frame
	check(player.attack_state == LanPlayer.AttackState.NONE and player.defense_state != LanPlayer.DefenseState.NONE, "K cancels sword wave into parry")
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

	current_scene = null
	world.free()
	assist.set_player_invincible(was_invincible)
	finish("SWORD WAVE")

extends SceneTree


const MAP_HALF_WIDTH := 1920.0
const ACTOR_LIMIT := 1824.0
const MAX_COMBAT_SEPARATION := 1088.0


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func drive_boss_timeline(boss: Node, animation_name: StringName, frame: int) -> void:
	if boss.combat_timeline.current_animation != animation_name:
		boss.combat_timeline.play(animation_name)
		boss.combat_timeline.seek(0.0, true)
	boss.combat_timeline.seek(float(frame) / 10.0, true)


func require_nonempty_animation_frames(
	sprite: AnimatedSprite2D,
	animation_name: StringName,
	expected_frame_count: int
) -> bool:
	var frames := sprite.sprite_frames
	if not require(
		frames.get_frame_count(animation_name) == expected_frame_count,
		"%s body animation frame count changed" % animation_name
	):
		return false
	for frame_index in expected_frame_count:
		var texture := frames.get_frame_texture(animation_name, frame_index)
		var image := texture.get_image() if texture != null else null
		if not require(
			image != null and image.get_used_rect().has_area(),
			"%s body animation frame %d is blank" % [animation_name, frame_index + 1]
		):
			return false
	return true


func run_test() -> void:
	var room := (load("res://scenes/sideview/tutorial_battle_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame

	var player := room.get_node("Lan") as CharacterBody2D
	var boss := room.get_node("MasterBoss") as Node2D
	var dummy := room.get_node("TrainingDummy") as DamageReceiver2D
	var camera := room.get_node("BattleCamera") as Camera2D
	var battle_assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	battle_assist.set_level(BattleAssistSettingsService.Level.NONE)
	var expected_timeline_frames := {
		&"attack_1": 11,
		&"attack_2": 19,
		&"attack_3": 28,
		&"special_attack": 18,
	}
	for animation_name: StringName in expected_timeline_frames:
		var timeline_animation: Animation = boss.combat_timeline.get_animation(animation_name)
		if not require(timeline_animation != null, "Boss combat timeline is missing %s" % animation_name):
			return
		if not require(
			timeline_animation.track_get_path(0) == NodePath("AnimatedSprite2D:frame")
			and timeline_animation.track_get_path(1) == NodePath("WindEffect:frame")
			and timeline_animation.track_get_key_count(0) == expected_timeline_frames[animation_name]
			and timeline_animation.track_get_key_count(1) == expected_timeline_frames[animation_name],
			"%s does not drive body and FX from the same complete timeline" % animation_name
		):
			return
		if animation_name != &"special_attack" and not require_nonempty_animation_frames(
			boss.animated_sprite,
			animation_name,
			expected_timeline_frames[animation_name]
		):
			return
	if not require(boss.combat_timeline.callback_mode_process == 0, "Boss combat timeline is not physics-processed"):
		return

	boss.position.x = ACTOR_LIMIT
	player.position.x = -MAP_HALF_WIDTH
	player._physics_process(0.0)
	room._process(0.0)

	if not require(
		absf(player.position.x - boss.position.x) <= MAX_COMBAT_SEPARATION,
		"Player and boss exceeded the one-screen combat span"
	):
		return
	if not require(
		player.position.x >= -ACTOR_LIMIT and player.position.x <= ACTOR_LIMIT,
		"Player escaped the three-screen map bounds"
	):
		return
	if not require(
		camera.position.x <= MAP_HALF_WIDTH - 640.0,
		"Battle camera escaped the right map limit"
	):
		return

	player.position.x = 0.0
	boss.position.x = 0.0
	camera.position.x = 0.0
	player.position.x = 1000.0
	player.ultimate_active = true
	room._process(0.0)
	if not require(is_equal_approx(camera.position.x, 0.0), "Battle camera followed Lan's nonphysical ultimate traversal"):
		return
	player.ultimate_active = false
	player.position.x = 0.0
	player.position.x = 1000.0
	room._process(0.0)
	if not require(is_equal_approx(boss.position.x, 0.0), "Player camera movement changed boss position"):
		return
	if not require(
		absf(boss.position.x - camera.position.x) > 640.0 - 96.0,
		"Boss was not allowed to leave the player-led camera"
	):
		return

	player.position.x = 1000.0
	boss.set("state", 0)
	boss.set("punish_dash_cooldown_remaining", 0.0)
	boss._process(0.25)
	boss._process(0.25)
	if not require(boss.position.x > 0.0, "Boss did not trigger the long-range punish dash"):
		return
	if not require(int(boss.get("state")) == 3, "Boss punish dash state ended before reaching its aggro target"):
		return

	player.position.x = 0.0
	boss.position.x = 100.0
	boss.set("state", 0)
	boss._process(0.0)
	if not require(boss.animated_sprite.animation == &"attack_1", "Boss did not start its first attack in range"):
		return
	if not require(boss.wind_effect.visible, "Boss attack did not enable its wind effect"):
		return
	var health_before := int(player.combat_stats.health)
	drive_boss_timeline(boss, &"attack_1", 4)
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	if not require(int(player.combat_stats.health) < health_before, "Boss active hitbox did not damage Lan"):
		return

	var boss_poise_before := int(boss.combat_stats.poise)
	boss.set("state", 1)
	boss.on_attack_parried(boss.attack_hitbox.attack)
	if not require(int(boss.combat_stats.poise) == boss_poise_before - boss.PARRY_POISE_DAMAGE, "Successful parry did not damage boss poise"):
		return
	if not require(int(boss.get("state")) == 1 and boss.animated_sprite.animation == &"attack_1", "Successful parry interrupted the boss attack"):
		return
	if not require(boss.parry_pause_remaining == boss.PARRY_PAUSE_DURATION and not boss.combat_timeline.is_playing(), "Successful parry did not pause the current attack for one frame"):
		return
	var flash_material := boss.animated_sprite.material as ShaderMaterial
	if not require(is_equal_approx(float(flash_material.get_shader_parameter(&"flash_amount")), 1.0), "Successful parry did not start the white flash"):
		return
	var flash_shader_code := flash_material.shader.code
	if not require(
		"vec4 base = COLOR" in flash_shader_code
		and "mix(base.rgb, flash_color.rgb, flash_amount)" in flash_shader_code
		and "texture(TEXTURE, UV)" not in flash_shader_code,
		"Boss flash shader does not preserve the unflashed sprite color",
	):
		return
	boss._update_parry_feedback(boss.PARRY_PAUSE_DURATION)
	if not require(int(boss.get("state")) == 1 and boss.animated_sprite.animation == &"attack_1" and boss.combat_timeline.is_playing(), "Boss attack did not resume from the paused animation"):
		return

	var boss_health_before := int(boss.combat_stats.health)
	boss.receive_hit(1, player.global_position)
	if not require(int(boss.combat_stats.health) == boss_health_before - boss.PLAYER_HIT_HEALTH_DAMAGE, "Lan attack damage was not applied to the boss"):
		return
	while boss.combat_stats.poise > 0:
		boss.receive_hit(1, player.global_position)
	if not require(boss.poise_broken and int(boss.get("state")) == 1 and boss.animated_sprite.animation == &"attack_1", "Poise depletion incorrectly interrupted the boss attack"):
		return
	if not require(boss.interrupt_with_break_special(), "Break-only special could not interrupt a poise-broken boss"):
		return
	if not require(int(boss.get("state")) == 2 and boss.animated_sprite.animation == &"hurt", "Break-only special did not enter stagger recovery"):
		return
	boss._update_recovery(boss.POISE_BREAK_RECOVERY_TIME)
	if not require(boss.poise_broken and boss.combat_stats.poise < boss.combat_stats.max_poise, "Boss poise refilled when the hit reaction ended"):
		return

	dummy.position.x = 1000.0
	player.position = Vector2(0.0, SideviewMapLayout.GROUND_BASELINE_Y)
	boss.position = Vector2(100.0, SideviewMapLayout.GROUND_BASELINE_Y)
	var attack_health_before := int(boss.combat_stats.health)
	player.attack_state = player.AttackState.NONE
	player.start_attack_1x(1.0)
	player._timeline_attack_1_effect_frame(0)
	if not require(player.active_attack_effects.size() == 1, "Lan attack did not spawn its effect hitbox"):
		return
	var player_effect = player.active_attack_effects[0]
	player_effect.animated_sprite.frame = 1
	player_effect.update_hitbox_for_frame()
	await physics_frame
	await physics_frame
	player_effect._physics_process(0.0)
	if not require(int(boss.combat_stats.health) < attack_health_before, "Lan attack hitbox did not damage the boss"):
		return

	player.cancel_uncommitted_attack_effects()
	player.attack_state = player.AttackState.NONE
	player.defense_state = player.DefenseState.NONE
	player.hit_reaction_active = false
	player.ground_knockback_active = false
	player.combat_stats.health = player.combat_stats.max_health
	player.position = Vector2(0.0, SideviewMapLayout.GROUND_BASELINE_Y)
	boss.position = Vector2(100.0, SideviewMapLayout.GROUND_BASELINE_Y)
	boss.movement_direction = -1.0
	boss.apply_facing_direction()
	boss.state = boss.State.ATTACK
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_2", 11)
	var attack_rectangle := boss.attack_collision_shape.shape as RectangleShape2D
	if not require(boss.attack_hitbox.position == Vector2(8.5, 92.0) and attack_rectangle.size == Vector2(274.0, 71.0), "Attack 2 frame 12 hitbox did not follow its wind FX bounds"):
		return
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	var segment_two_health: int = int(player.combat_stats.health)
	if not require(segment_two_health == player.combat_stats.max_health - boss.ATTACK_DAMAGE, "Attack 2 second segment did not deal exactly one hit"):
		return
	drive_boss_timeline(boss, &"attack_2", 12)
	if not require(boss.attack_hitbox.position == Vector2(89.5, 48.5) and attack_rectangle.size == Vector2(256.0, 110.0), "Attack 2 frame 13 hitbox did not move and resize with its wind FX"):
		return
	boss.attack_hitbox._physics_process(0.0)
	if not require(player.combat_stats.health == segment_two_health, "Consecutive active frames dealt repeated damage within one segment"):
		return
	drive_boss_timeline(boss, &"attack_2", 13)
	if not require(not boss.attack_hitbox.monitoring, "Attack 2 gap frame did not close the previous hit window"):
		return
	drive_boss_timeline(boss, &"attack_2", 14)
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	if not require(player.combat_stats.health == segment_two_health - boss.ATTACK_DAMAGE, "Attack 2 third segment did not deal its separate hit"):
		return
	if not require(player.ground_knockback_active and not is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.y), "Attack 2 third segment did not apply ground-only knockback"):
		return

	battle_assist.set_level(BattleAssistSettingsService.Level.NONE)
	if not require(battle_assist.get_red_slowdown() == Vector2(1.0, 0.0) and battle_assist.get_normal_slowdown() == Vector2(1.0, 0.0), "Assist level 1 unexpectedly slowed boss attacks"):
		return
	battle_assist.set_level(BattleAssistSettingsService.Level.LIGHT)
	if not require(battle_assist.get_red_slowdown() == Vector2(0.70, 0.25) and battle_assist.get_normal_slowdown() == Vector2(1.0, 0.0), "Assist level 2 timings do not match the design"):
		return
	battle_assist.set_level(BattleAssistSettingsService.Level.STRONG)
	if not require(battle_assist.uses_contact_parry_prompt() and battle_assist.get_red_slowdown() == Vector2(1.0, 0.0) and battle_assist.get_normal_slowdown() == Vector2(1.0, 0.0), "Assist level 3 still uses the obsolete percentage slowdown"):
		return

	battle_assist.set_level(BattleAssistSettingsService.Level.LIGHT)
	boss.state = boss.State.ATTACK
	drive_boss_timeline(boss, &"attack_3", 19)
	if not require(boss.danger_warning.visible and boss.danger_warning.animation == &"red", "Attack 3 fourth segment did not emit its red warning"):
		return
	var red_warning_material := boss.animated_sprite.material as ShaderMaterial
	if not require(is_zero_approx(float(red_warning_material.get_shader_parameter(&"flash_amount"))), "Red warning tinted the entire boss model"):
		return
	if not require(is_equal_approx(boss.combat_timeline.speed_scale, 0.70) and is_equal_approx(boss.assist_slow_remaining, 0.25), "Light assist did not apply the red 70% / 250ms slowdown"):
		return
	boss._update_assist_slowdown(0.36)
	if not require(is_equal_approx(boss.combat_timeline.speed_scale, 1.0), "Red slowdown did not restore the boss animation speed"):
		return

	player.finish_hit_reaction()
	player.defense_state = player.DefenseState.NONE
	player.combat_stats.health = player.combat_stats.max_health
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_3", 22)
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	if not require(player.combat_stats.health == player.combat_stats.max_health - boss.RED_ATTACK_DAMAGE, "Attack 3 red segment did not apply elevated red damage"):
		return

	player.finish_hit_reaction()
	player.start_parry(true)
	boss.combat_stats.restore_poise()
	boss.poise_broken = false
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_3", 21)
	drive_boss_timeline(boss, &"attack_3", 22)
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	if not require(boss.combat_stats.poise == boss.combat_stats.max_poise - boss.RED_PARRY_POISE_DAMAGE, "Successful red parry did not apply elevated poise damage"):
		return

	player.finish_defense()
	player.position = Vector2(0.0, SideviewMapLayout.GROUND_BASELINE_Y)
	player.combat_stats.health = player.combat_stats.max_health
	boss.position = Vector2(100.0, SideviewMapLayout.GROUND_BASELINE_Y)
	boss.movement_direction = -1.0
	boss.apply_facing_direction()
	boss.state = boss.State.ATTACK
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	boss.attack_hitbox.deactivate()
	battle_assist.set_level(BattleAssistSettingsService.Level.STRONG)
	player.air_state = player.AirState.GROUNDED
	player.attack_state = player.AttackState.DODGE_ATTACK_2X
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring, "Dodge attack 2 startup incorrectly opened the contact parry prompt"):
		return
	boss.attack_hitbox.deactivate()
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.FALLING
	player.velocity.y = 100.0
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring, "Airborne Lan incorrectly opened the contact parry prompt"):
		return
	boss.attack_hitbox.deactivate()
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	player.air_state = player.AirState.GROUNDED
	player.velocity.y = 0.0
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(boss.contact_parry_active and boss.parry_assist_prompt.visible and is_equal_approx(boss.combat_timeline.speed_scale, boss.CONTACT_PARRY_BOSS_SPEED), "Strong assist did not open the contact parry prompt for an overlapping attack"):
		return
	if not require(boss.parry_assist_key_label.text == "K" and is_equal_approx(boss.contact_parry_remaining, 1.0), "Contact parry prompt did not show the configured key and one-second timer"):
		return
	player.non_parry_action_requested.emit()
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring and is_equal_approx(boss.combat_timeline.speed_scale, 1.0), "A non-parry action did not immediately dismiss the contact prompt"):
		return
	boss.attack_hitbox.deactivate()
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(boss.contact_parry_active, "Contact prompt did not reopen for the parry success check"):
		return
	var prompt_poise_before: int = int(boss.combat_stats.poise)
	boss._resolve_contact_parry_success()
	if not require(not boss.contact_parry_active and player.defense_state == player.DefenseState.PARRY_SUCCESS and boss.combat_stats.poise < prompt_poise_before, "Contact prompt input did not resolve as a guaranteed parry"):
		return

	boss._update_parry_feedback(boss.PARRY_PAUSE_DURATION)
	player.finish_defense()
	player.combat_stats.health = player.combat_stats.max_health
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_1", 3)
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(boss.contact_parry_active, "Second attack did not create a fresh contact prompt"):
		return
	boss._resolve_contact_parry_timeout()
	await physics_frame
	await physics_frame
	boss.attack_hitbox._physics_process(0.0)
	if not require(player.combat_stats.health == player.combat_stats.max_health - boss.ATTACK_DAMAGE, "Expired contact prompt did not restore the real attack collision"):
		return

	player.position.x = 1000.0
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_1", 3)
	drive_boss_timeline(boss, &"attack_1", 4)
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring, "Out-of-range attack incorrectly opened the contact prompt"):
		return

	player.position.x = 0.0
	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_3", 10)
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring, "Attack 3 second segment incorrectly prompted before its FX reached Lan"):
		return
	drive_boss_timeline(boss, &"attack_3", 11)
	if not require(boss.contact_parry_active, "Attack 3 second segment failed to prompt when its later FX frame swept into Lan"):
		return
	boss._cancel_contact_parry_prompt()

	boss.attack_serial += 1
	boss.active_hit_segment = -1
	boss.assisted_segments.clear()
	boss.attack_hitbox.deactivate()
	drive_boss_timeline(boss, &"attack_3", 13)
	if not require(not boss.contact_parry_active and boss.attack_hitbox.monitoring, "Attack 3 third segment incorrectly prompted before its FX reached Lan"):
		return
	drive_boss_timeline(boss, &"attack_3", 14)
	if not require(boss.contact_parry_active, "Attack 3 third segment failed to prompt when its later FX frame swept into Lan"):
		return
	boss._cancel_contact_parry_prompt()

	var gold_attack := CombatAttackData.new(&"gold_test", boss, 20, 12, 0.0, 0.0, CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	if not require(not boss._should_start_contact_parry(99, gold_attack), "Gold attack incorrectly allowed the parry prompt"):
		return

	if not require(
		boss.has_node("BossStatusHUD")
		and boss.animated_sprite.sprite_frames.get_frame_count(&"phase_2_transform") == boss.PHASE_2_TRANSFORM_FRAME_COUNT
		and boss.animated_sprite.sprite_frames.get_frame_count(&"phase_2_idle") == 24,
		"Boss HUD or phase 2 presentation animations are incomplete"
	):
		return
	boss.combat_timeline.play(&"attack_1")
	boss._on_attack_hit_resolved(player, CombatHitResult.Type.NORMAL_HIT)
	if not require(boss.charged_power == 0, "A normal boss attack incorrectly added charged power"):
		return
	boss.combat_timeline.play(&"special_attack")
	boss._on_attack_hit_resolved(player, CombatHitResult.Type.EVADED)
	if not require(boss.charged_power == 0, "An avoided charged attack incorrectly added charged power"):
		return
	for expected_stack in range(1, boss.CHARGED_POWER_MAX + 1):
		boss.attack_serial += 1
		boss.combat_timeline.play(&"special_attack")
		boss._on_attack_hit_resolved(player, CombatHitResult.Type.NORMAL_HIT)
		if not require(boss.charged_power == expected_stack, "A landed charged attack did not add exactly one stack"):
			return
		boss._on_attack_hit_resolved(player, CombatHitResult.Type.NORMAL_HIT)
		if not require(boss.charged_power == expected_stack, "One charged attack added more than one stack"):
			return
	if not require(
		boss.phase == 2
		and int(boss.state) == boss.State.TRANSFORM
		and boss.combat_stats.health == boss.combat_stats.max_health
		and boss.animated_sprite.animation == &"phase_2_transform",
		"Four charged-attack hits did not start phase 2 with a full second health bar"
	):
		return
	boss._on_body_animation_finished()
	if not require(
		int(boss.state) == boss.State.PHASE_2_IDLE
		and boss.animated_sprite.animation == &"phase_2_idle",
		"Boss did not settle into phase 2 idle after transforming"
	):
		return

	print("Tutorial battle space checks passed")
	quit()
